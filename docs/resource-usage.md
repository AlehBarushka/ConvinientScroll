# Потребление ресурсов

Строки добавляет `scripts/measure-resources.sh`; когда мерить, сказано в `CLAUDE.md` («Замер ресурсов»).
CPU — процессорное время процесса за окно замера; пробуждения — idle wakeups в секунду; Energy — среднее
`POWER` из `top` (то же, что «Energy Impact» в Activity Monitor); память — `footprint`.

| Дата | Версия | Сборка | Коммит | Модули | Сценарий | Окно, с | CPU, % | CPU, мс/мин | Пробуждения/с | Energy | Память, МБ | Mac |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-22 | 2.3.0 (11) | installed | release | autoScroll shelf memory | baseline before thermal: memory on, menus closed | 180 | 0.067 | 40 | 0.76 | 0.06 | 18.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.3.0 (11) | release build | 1d1243a | autoScroll shelf memory thermal | thermal on, menus closed | 180 | 0.156 | 93 | 0.89 | 0.16 | 17.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.3.0 (11) | release build | 1d1243a | autoScroll shelf memory | thermal off (same build), menus closed | 180 | 0.100 | 60 | 0.69 | 0.10 | 18.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.3.0 (11) | release build | 8a33884 | autoScroll shelf memory thermal | final: thermal on, 10 min, menus closed | 600 | 0.202 | 121 | 1.01 | 0.20 | 18.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.3.0 (11) | release build | 8a33884 | autoScroll shelf memory | final: thermal off (same build), after 2 min warm-up, menus closed | 180 | 0.039 | 23 | 0.55 | 0.04 | 15.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.3.0 (11) | release build | 230f3ed | autoScroll shelf memory thermal | after CPU cut: thermal on, 10 min, menus closed | 600 | 0.113 | 68 | 0.73 | 0.10 | 17.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.3.0 (11) | release build | 230f3ed | autoScroll shelf memory | after CPU cut: thermal off (same build), after 2 min warm-up, menus closed — недействителен: в середине замера погас экран, таймеры стояли | 180 | 0.006 | 3 | 0.03 | 0.01 | 15.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.0 (12) | release build | 605ccaa+dirty | autoScroll shelf memory thermal | release candidate: thermal on, 10 min, menus closed | 600 | 0.072 | 43 | 0.56 | 0.05 | 15.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.0 (12) | release build | 605ccaa+dirty | autoScroll shelf memory | release candidate: thermal off (same build), after 2 min warm-up, menus closed | 180 | 0.050 | 30 | 0.50 | 0.04 | 15.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.0 (12) | installed | release | autoScroll shelf memory thermal | baseline before apps module: autoScroll shelf memory thermal, menus closed | 120 | 0.100 | 60 | 0.97 | 0.10 | 35.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.0 (12) | release build | 6c727f6+dirty | autoScroll shelf memory thermal | core sensors (SMC): thermal on, 10 min, menus closed | 600 | 0.113 | 68 | 0.81 | 0.11 | 19.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.0 (12) | release build | 6c727f6+dirty | autoScroll shelf memory | core sensors (SMC): thermal off (same build), after 2 min warm-up, menus closed | 180 | 0.044 | 27 | 0.48 | 0.04 | 17.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.0 (12) | release build | 08b2fa2 | autoScroll shelf memory thermal | single menu bar item: autoScroll shelf memory thermal, 10 min, menus closed — недействителен: во время замера шли компиляции, из-за нагрузки цифры памяти и температуры менялись непрерывно; причина роста (дрожание памяти на границе округления и пересоздание картинок при каждой перерисовке) исправлена следующим коммитом | 600 | 0.413 | 248 | 1.70 | 0.43 | 38.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.1 (13) | release build | 6ce7c48 | autoScroll shelf memory thermal | single menu bar item after the redraw fix: autoScroll shelf memory thermal, 10 min, menus closed | 600 | 0.100 | 60 | 0.75 | 0.09 | 19.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.1 (13) | release build | bc0c46c | autoScroll shelf memory thermal | control for apps module: fresh master build bc0c46c (no apps module), after 2 min warm-up, menus closed | 120 | 0.033 | 20 | 0.44 | 0.01 | 18.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.1 (13) | release build | 7a8479c | autoScroll shelf memory thermal apps | apps module on, window closed, after 2 min warm-up, menus closed | 120 | 0.075 | 45 | 0.63 | 0.06 | 24.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.1 (13) | release build | 7a8479c | autoScroll shelf memory thermal | apps module off (same build), after 2 min warm-up, menus closed | 120 | 0.075 | 45 | 0.72 | 0.06 | 19.0 | Mac17,2, Apple M5, macOS 26.7.3 |
| 2026-11-22 | 2.4.1 (13) | release build | 7a8479c | autoScroll shelf memory thermal apps | apps module on, window closed, 10 min, menus closed | 600 | 0.098 | 59 | 0.70 | 0.09 | 20.0 | Mac17,2, Apple M5, macOS 26.7.3 |
