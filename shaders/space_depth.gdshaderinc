// Avaruuden kappaleiden syvyys: aina ohjaamon taakse, järjestys etäisyyden mukaan. Molemmat renderöijät
// käyttävät käänteistä syvyyttä (1 = lähitaso, 0 = kaukotaso): ohjaamon pinnat (alle 3 m) ovat noin 0,007,
// avaruus alle 1e-5.
float space_depth(vec3 view_pos) {
	return 1e-8 + 1e-5 * (1.0 - clamp(length(view_pos) / 1.2e5, 0.0, 1.0));
}
