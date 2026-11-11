import json, os, subprocess, sys, tempfile, unittest, types
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools", "import"))
import osm_to_network, gtfs_schedule, validate_networks

FIX = os.path.join(os.path.dirname(__file__), "fixtures", "import")
ROOT = os.path.join(os.path.dirname(__file__), "..")


class T(unittest.TestCase):
    def args(self):
        return types.SimpleNamespace(id="mini", city="X", line="1", supply="overhead", guidance="steel",
                                     default_limit=50, snap_m=30.0, osm_date="test")

    def test_osm(self):
        net = osm_to_network.build(json.load(open(os.path.join(FIX, "mini_osm.json"))), self.args())
        self.assertEqual(len(net["edges"]), 6)  # 3 ways x 2 sens
        self.assertEqual(net["stations"][0]["name"], "Mairie")
        st = net["stations"][0]
        L = {e["id"]: e["length"] for e in net["edges"]}[st["edge"]]
        self.assertTrue(0 <= st["offset"] <= L)
        self.assertTrue(st["offset"] > 100 or st["offset"] < 1)
        lim = {e["limit_kmh"] for e in net["edges"] if e["id"].startswith("w10")}
        self.assertEqual(lim, {40})
        errs, _ = validate_networks.validate(net)
        self.assertEqual(errs, [])

    def test_gtfs(self):
        s = gtfs_schedule.schedule(os.path.join(FIX, "gtfs"), "A")
        self.assertEqual([x["name"] for x in s["stops"]], ["Alpha", "Beta"])
        self.assertEqual(s["stops"][1]["departure_s"], 6 * 3600 + 3 * 60 + 40)

    def test_validator_detects(self):
        bad = {"schema": 1, "supply": "x", "nodes": ["A"], "edges": [{"id": "e", "from": "A", "to": "B", "length": -1}],
               "stations": [{"name": "s", "edge": "zz", "offset": 0}]}
        errs, _ = validate_networks.validate(bad)
        self.assertGreaterEqual(len(errs), 4)

    def test_shipped_data_valid(self):
        d = os.path.join(ROOT, "data", "networks")
        for f in os.listdir(d):
            errs, _ = validate_networks.validate(json.load(open(os.path.join(d, f))))
            self.assertEqual(errs, [], f)


if __name__ == "__main__":
    unittest.main()
