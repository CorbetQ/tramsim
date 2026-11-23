"""Explicitly fictional combinations for the family selector; originals stay untouched."""
from copy import deepcopy


def add_examples(entries):
    combinations = [
        ('angers__concept_citadis_205', 'angers__citadis_x05', 'angers', 'Angers', 'Citadis 205 Irigo', 'citadis_compact', 24.0, 3),
        ('nantes__concept_citadis_205', 'nantes__citadis_x05_nantes', 'nantes', 'Nantes', 'Citadis 205 Naolib', 'citadis_x05_nantes', 24.0, 3),
        ('nantes__concept_tfs_2', 'idf__tfs__t1', 'nantes', 'Nantes', 'Alsthom TFS 2 TAN', 'tfs', 29.4, 3),
        ('idf__concept_tfs_1', 'nantes__tfs', 'idf', 'Île-de-France', 'Alsthom TFS 1 RATP', 'tfs', 36.5, 3),
    ]
    by_id = {e['id']: e for e in entries}
    for vid, origin, network, city, name, family, length, count in combinations:
        if vid in by_id:
            continue
        entry = deepcopy(by_id[origin])
        entry.update(id=vid, inspired_by=origin, network=network, city=city, name=name+' — concept',
                     family=family, length=length, module_count=count, fictional=True, lines=[], line='',
                     fiction_note='Combinaison fictive demandée pour le catalogue ; aucune rame réelle de ce réseau.',
                     status='fictional', estimated=['mass_t','power_kw','capacity','geometry','length_m','width_m'])
        entry['geometry']['modules'] = count
        entry['technical'].update(mass_t=round(length*1.25,1), capacity=round(length*6.4))
        for ref in entry.get('references', []):
            ref['role'] = 'Référence de forme du matériel source, pas de cette combinaison fictive.'
        entries.append(entry)
