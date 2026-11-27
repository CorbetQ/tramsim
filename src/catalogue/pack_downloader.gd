class_name PackDownloader
extends Node
## Client de téléchargement des packs (docs/SERVEUR_DONNEES.md) : manifeste (serveur puis release GitHub), file de
## packs, reprise (en-tête Range sur le fichier .part, y compris après coupure : nouvelles tentatives automatiques),
## vérification sha256 (pack rejeté si différente), annulation, contrôle de l'espace libre, installation dans
## user://packs (nom suffixé par l'empreinte : jamais d'écrasement d'un pack monté) et montage. Le réseau tourne dans
## un fil dédié ; l'état est relu dans _process et publié par signaux sur le fil principal.
signal manifest_done(ok: bool, error: String)
signal progress(id: String, done: int, total: int, speed: float)
signal finished(ok: bool, error: String)
const RETRIES := 3
const TIMEOUT_MS := 20000
const CHUNK := 262144
var user_agent := "TramSimFrance/" + CityPacks.game_version()
var _thread: Thread
var _mutex := Mutex.new()
var _cancel := false
var _state := {}
var _busy := false
var _kind := ""
var _speed := 0.0
var _speed_t := 0
var _speed_b := 0
var source: Dictionary = {}          # source retenue au dernier manifeste réussi

func busy() -> bool:
	return _busy

func cancel() -> void:
	_mutex.lock(); _cancel = true; _mutex.unlock()

func _put(k: String, v: Variant) -> void:
	_mutex.lock(); _state[k] = v; _mutex.unlock()

func _cancelled() -> bool:
	_mutex.lock(); var c := _cancel; _mutex.unlock()
	return c

func _start(kind: String, job: Callable) -> bool:
	if _busy: return false
	if _thread != null: _thread.wait_to_finish()
	_busy = true; _kind = kind; _cancel = false; _state = {"done": false, "bytes": 0, "total": 0, "id": ""}
	_speed = 0.0; _speed_t = Time.get_ticks_msec(); _speed_b = 0
	_thread = Thread.new(); _thread.start(job)
	return true

## Télécharge le manifeste (serveur puis repli). Émet manifest_done.
func fetch_manifest() -> bool:
	return _start("manifest", _run_manifest.bind(CityPacks.sources()))

## Télécharge les packs (ids) absents ou à mettre à jour, dépendances comprises. Émet progress puis finished.
func download(ids: Array) -> bool:
	return _start("download", _run_download.bind(ids.duplicate(), CityPacks.sources(), CityPacks.platform(), CityPacks.USER_DIR, ProjectSettings.globalize_path(CityPacks.USER_DIR)))

func _process(_dt: float) -> void:
	if not _busy: return
	_mutex.lock(); var s := _state.duplicate(); _mutex.unlock()
	var now := Time.get_ticks_msec()
	if now - _speed_t >= 500:
		var b := int(s.get("bytes", 0))
		var inst := float(maxi(b - _speed_b, 0)) * 1000.0 / float(now - _speed_t)
		_speed = inst if _speed == 0.0 else lerpf(_speed, inst, 0.4)
		_speed_t = now; _speed_b = b
	if _kind == "download" and str(s.get("id", "")) != "":
		progress.emit(str(s.id), int(s.get("bytes", 0)), int(s.get("total", 0)), _speed)
	if not s.get("done", false): return
	_thread.wait_to_finish(); _thread = null; _busy = false
	if _kind == "manifest":
		if s.get("manifest") is Dictionary:
			CityPacks.store_manifest(s.manifest); source = s.get("source", {})
		manifest_done.emit(s.get("manifest") is Dictionary, str(s.get("error", "")))
		return
	for rec in s.get("installed", []):
		CityPacks.record_install(rec.id, rec.file, rec.sha256, rec.size, rec.data_version)
	if s.get("manifest") is Dictionary: CityPacks.store_manifest(s.manifest)
	var err := str(s.get("error", ""))
	if err == "":
		for rec in s.get("installed", []):
			if CityPacks.mounted.has(rec.id): CityPacks.mounted.erase(rec.id)   # nouvelle version : remontée (remplace les fichiers)
			if not CityPacks.mount(rec.id): err = "Pack %s illisible après installation." % rec.id
	finished.emit(err == "", err)

func _exit_tree() -> void:
	cancel()
	if _thread != null: _thread.wait_to_finish(); _thread = null

# ------------------------------------------------------------------------------------------ fil de téléchargement

func _run_manifest(srcs: Array) -> void:
	var r := _fetch_manifest(srcs)
	_mutex.lock(); _state.merge(r, true); _state.done = true; _mutex.unlock()

func _fetch_manifest(srcs: Array) -> Dictionary:
	var errors: Array = []
	for src in srcs:
		for url in src.manifest:
			if _cancelled(): return {"error": "Annulé."}
			var r := _http_get(url, "", 0, null)
			if not r.ok: errors.append("%s : %s" % [src.name, r.error]); continue
			var man = JSON.parse_string((r.body as PackedByteArray).get_string_from_utf8())
			var why := CityPacks.incompatibility(man)
			if why != "": errors.append("%s : %s" % [src.name, why]); continue
			return {"manifest": man, "source": src}
	return {"error": "Serveur de données injoignable (" + "; ".join(errors) + ")."}

func _run_download(ids: Array, srcs: Array, plat: String, user_dir: String, disk_dir: String) -> void:
	var out := {"installed": []}
	var m := _fetch_manifest(srcs)
	if m.has("error"):
		out.error = m.error + " Hors ligne : seules les villes déjà téléchargées sont jouables."
		_finish(out); return
	var man: Dictionary = m.manifest; out.manifest = man
	var src: Dictionary = m.source
	var packs: Dictionary = man.platforms[plat]
	var queue: Array = []
	for id in ids:
		var deps: Array = packs.get(id, {}).get("requires", []) if not CityPacks.is_common(id) else []
		for d in deps + [id]:
			if d in queue: continue
			if not packs.has(d): out.error = "Pack « %s » absent du manifeste (%s)." % [d, man.get("data_version", "?")]; _finish(out); return
			var have: Dictionary = CityPacks.installed().get(d, {})
			if str(have.get("sha256", "")) == str(packs[d].sha256) and FileAccess.file_exists(user_dir.path_join(str(have.get("file", "")))): continue
			if not CityPacks.present(d) or not have.is_empty(): queue.append(d)
	var total := 0
	for id in queue: total += int(packs[id].size)
	var left := CityPacks.space_left()
	if left >= 0 and left < int(total * 1.05):
		out.error = "Espace insuffisant : %s nécessaires, %s libres." % [CityPacks.human_size(total), CityPacks.human_size(left)]
		_finish(out); return
	DirAccess.make_dir_recursive_absolute(user_dir)
	var base_done := 0
	for id in queue:
		var e: Dictionary = packs[id]
		var final_name := str(e.file).get_basename() + "." + str(e.sha256).substr(0, 12) + ".pck"
		var part := disk_dir.path_join(str(e.file) + ".part")
		var r := {}
		for attempt in RETRIES + 1:
			if _cancelled(): break
			r = _download_one(CityPacks.pack_url(src, e), part, e, base_done, total, id)
			if r.ok or r.get("fatal", false): break
			if not r.ok and src.name != "release" and attempt == 0:
				# serveur indisponible : repli sur la release GitHub (même pack attendu : même sha256)
				var rel := _fetch_manifest(srcs.filter(func(s): return s.name == "release"))
				var re: Dictionary = rel.get("manifest", {}).get("platforms", {}).get(plat, {}).get(id, {})
				if str(re.get("sha256", "")) == str(e.sha256): src = rel.source
			OS.delay_msec(500 * (attempt + 1))
		if _cancelled():
			out.error = "Téléchargement annulé (reprise possible)."; _finish(out); return
		if not r.ok:
			out.error = "Échec du téléchargement de %s : %s" % [str(e.get("label", id)), r.error]; _finish(out); return
		var dst := disk_dir.path_join(final_name)
		DirAccess.remove_absolute(dst)
		if DirAccess.rename_absolute(part, dst) != OK:
			out.error = "Installation impossible : " + final_name; _finish(out); return
		out.installed.append({"id": id, "file": final_name, "sha256": str(e.sha256), "size": int(e.size), "data_version": str(man.get("data_version", ""))})
		base_done += int(e.size)
	_finish(out)

func _finish(out: Dictionary) -> void:
	_mutex.lock(); _state.merge(out, true); _state.done = true; _mutex.unlock()

## Télécharge (ou reprend) un pack dans .part et vérifie taille et sha256.
func _download_one(url: String, part: String, e: Dictionary, base_done: int, total: int, id: String) -> Dictionary:
	var size := int(e.size)
	var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA256)
	var have := 0
	if FileAccess.file_exists(part):
		var f := FileAccess.open(part, FileAccess.READ)
		have = int(f.get_length())
		if have > size: f.close(); DirAccess.remove_absolute(part); have = 0
		else:
			while f.get_position() < have: ctx.update(f.get_buffer(CHUNK))
			f.close()
	_put("id", id); _put("total", total); _put("bytes", base_done + have)
	if have < size:
		var r := _http_get(url, part, have, ctx, base_done)
		if not r.ok:
			if r.get("restart", false): DirAccess.remove_absolute(part)
			return r
		if r.get("restarted", false):
			ctx = r.ctx
	var got := int(FileAccess.open(part, FileAccess.READ).get_length()) if FileAccess.file_exists(part) else 0
	if got != size:
		return {"ok": false, "error": "taille %d au lieu de %d (coupure)" % [got, size]}
	var sha := ctx.finish().hex_encode()
	if sha != str(e.sha256):
		DirAccess.remove_absolute(part)
		return {"ok": false, "fatal": true, "error": "somme de contrôle sha256 invalide : pack rejeté"}
	return {"ok": true}

static func _split(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := hostport; var port := 443 if tls else 80
	if hostport.contains(":"):
		host = hostport.get_slice(":", 0); port = int(hostport.get_slice(":", 1))
	return {"tls": tls, "host": host, "port": port, "path": path}

## GET (fil de téléchargement). dest "" : corps en mémoire (body). Sinon ajout à dest à partir de offset (Range),
## avec hachage incrémental (ctx). Suit les redirections (release GitHub -> stockage).
func _http_get(url: String, dest: String, offset: int, ctx: HashingContext, base_done := 0, redirects := 0) -> Dictionary:
	var u := _split(url)
	var c := HTTPClient.new()
	c.read_chunk_size = CHUNK
	if c.connect_to_host(u.host, u.port, TLSOptions.client() if u.tls else null) != OK:
		return {"ok": false, "error": "connexion impossible à " + str(u.host)}
	var t0 := Time.get_ticks_msec()
	while c.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		c.poll(); OS.delay_msec(5)
		if _cancelled(): return {"ok": false, "error": "annulé"}
		if Time.get_ticks_msec() - t0 > TIMEOUT_MS: return {"ok": false, "error": "délai de connexion dépassé"}
	if c.get_status() != HTTPClient.STATUS_CONNECTED: return {"ok": false, "error": "serveur injoignable (%s)" % u.host}
	var headers := ["User-Agent: " + user_agent, "Accept: */*", "Accept-Encoding: identity"]
	if offset > 0: headers.append("Range: bytes=%d-" % offset)
	if c.request(HTTPClient.METHOD_GET, u.path, headers) != OK: return {"ok": false, "error": "requête refusée"}
	t0 = Time.get_ticks_msec()
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		c.poll(); OS.delay_msec(5)
		if _cancelled(): return {"ok": false, "error": "annulé"}
		if Time.get_ticks_msec() - t0 > TIMEOUT_MS: return {"ok": false, "error": "pas de réponse"}
	if not c.has_response(): return {"ok": false, "error": "connexion interrompue"}
	var code := c.get_response_code()
	var rh := c.get_response_headers_as_dictionary()
	if code in [301, 302, 303, 307, 308]:
		var loc := ""
		for k in rh:
			if str(k).to_lower() == "location": loc = str(rh[k])
		if loc == "" or redirects > 5: return {"ok": false, "error": "redirection invalide"}
		if loc.begins_with("/"): loc = ("https://" if u.tls else "http://") + str(u.host) + ":" + str(u.port) + loc
		return _http_get(loc, dest, offset, ctx, base_done, redirects + 1)
	var restarted := false
	if offset > 0 and code == 200:
		offset = 0; restarted = true   # Range ignoré : reprise depuis le début
		ctx = HashingContext.new(); ctx.start(HashingContext.HASH_SHA256)
	elif code == 416:
		return {"ok": false, "restart": true, "error": "reprise refusée (416)"}
	elif code != 200 and code != 206:
		return {"ok": false, "fatal": code == 404, "error": "HTTP %d" % code}
	var expected := int(c.get_response_body_length())
	var body := PackedByteArray()
	var f: FileAccess = null
	if dest != "":
		f = FileAccess.open(dest, FileAccess.READ_WRITE if offset > 0 and FileAccess.file_exists(dest) else FileAccess.WRITE)
		if f == null: return {"ok": false, "fatal": true, "error": "écriture impossible"}
		f.seek(offset)
	var got := offset
	var last := Time.get_ticks_msec()
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() - last > TIMEOUT_MS: break
			OS.delay_msec(2)
		else:
			last = Time.get_ticks_msec(); got += chunk.size()
			if f != null:
				f.store_buffer(chunk); ctx.update(chunk); _put("bytes", base_done + got)
			else: body.append_array(chunk)
		if _cancelled(): break
	if f != null: f.close()
	c.close()
	if _cancelled(): return {"ok": false, "error": "annulé"}
	if expected >= 0 and got - offset < expected: return {"ok": false, "error": "coupure après %d octets" % got}
	return {"ok": true, "code": code, "body": body, "restarted": restarted, "ctx": ctx}
