% =====================================================================
%  APS 4060S + B-G431B-ESC1  —  PARAMETRY DO EDYCJI
%  PLECS: Simulation parameters > Initialization:
%     run('aps4060_params.m'); run('aps4060_derived.m');
%  Pliki .m trzymaj w tym samym folderze co wiertlo.plecs
% =====================================================================

%% --- Zrodlo parametrow elektrycznych ---
%  'pomiar'   = wlasne pomiary 17.11.2026 (U/I 3 pary + L metoda szeregowego R)
%  'profiler' = ST Motor Profiler (do porownania)
src = 'pomiar';

% ST Motor Profiler
Rs_prof = 0.2;         % [Ohm] faza
Ls_prof = 0.19e-3;     % [H]   Ld = Lq

% Pomiar: R_LL z regresji U = R*I + U0 (0.15-2.25 A): rb 0.539, yb 0.546, yr 0.555 Ohm
%         L_LL para ab: 0.586 mH @1 kHz, 0.579 mH @2 kHz (jedno polozenie wirnika!)
R_LL_meas = mean([0.539 0.546 0.555]);   % [Ohm] linia-linia
L_LL_meas = mean([0.586e-3 0.579e-3]);   % [H]   linia-linia
T_meas    = 20;        % [degC] temperatura uzwojen przy pomiarze  <-- WPISZ jesli znasz
T_wind    = 20;        % [degC] temperatura do symulacji (np. 80 = goracy silnik)
alpha_cu  = 0.00393;   % [1/K] wspolczynnik temperaturowy miedzi

%% --- Pozostale parametry silnika (profiler) ---
p        = 7;          % pary biegunow (jak w profilerze!)
Ke       = 6.95;       % [Vrms L-L / krpm]
J_rotor  = 8.47e-6;    % [kg m^2] wirnik
Bf       = 3.84e-6;    % [N m s/rad] tarcie lepkie

%% --- Mechanika napedu (od mechanikow) ---
% coupling_after_gear = 1:  silnik -> przekladnia N -> sprzeglo -> wiertlo [J_C] -> gleba
% coupling_after_gear = 0:  silnik -> sprzeglo -> przekladnia N -> wiertlo [J_C] -> gleba
% Pomijamy bezwladnosc kol zebatych, walkow i sprzegla (male wobec wirnika i wiertla)
% J_C RZECZYWISTE (bez /N^2 - robi to blok Gear); SolidWorks g*mm^2 * 1e-9 = kg*m^2
coupling_after_gear = 1;
N_gear   = 4;          % przelozenie (n_silnika / n_wiertla) -> blok Gear: g = 1/N_gear
eta_gear = 0.9;        % sprawnosc przekladni (0..1) -> skaluje obciazenie (Gear jest idealny)
J_C = 36867e-9;        % [kg m^2] wiertlo z CAD (36867 g*mm^2) -> blok Inertia "J_wiertla" za Gear

%% --- Sprzeglo elastyczne (karta katalogowa) ---
K_c    = 110;          % [Nm/rad] ZALOZENIE: klowe ROTEX 14 98ShA (6.4 deg przy 12.5 Nm); belkowe Al ~500
zeta_c = 0.08;         % tlumienie wzgledne: metal ~0.01-0.05, elastomer (pajak) ~0.05-0.1

%% --- Zasilanie i plytka ---
Vbus   = 36.00;         % [V] zasilanie w symulacji (6S)
Vbus_wb = 15.89;       % [V] napiecie, dla ktorego Workbench liczyl nastawy pradu
Imax   = 30;           % [A pk] limit pradu fazowego
Rsh    = 0.003;        % [Ohm] bocznik
Gamp   = 9.14;         % wzmocnienie toru pradu
Vref   = 3.3;          % [V] ADC
fpwm   = 20e3;         % [Hz] PWM = petla pradu
fspd   = 1e3;          % [Hz] petla predkosci
maxmod = 0.95;         % max modulation index

%% --- Nastawy petli pradu ---
%  'workbench'   = liczby wpisane ponizej (jak w MC Workbench)
%  'przeskaluj'  = nastawy Workbench przeliczone z (Rs,Ls)_profiler na aktywne (Rs,Ls):
%                  to samo pasmo i to samo zero co zaprojektowal Workbench
%  'projekt'     = od zera: Kp = Ls*wc_i, Ki = Rs*wc_i (kompensacja bieguna R/L)
gain_mode_i = 'projekt';
wc_i        = 5000;    % [rad/s] pasmo dla trybu 'projekt'

Kp_i_wb = 9196;  KpDIV_i = 1024;     % Torque/Flux Kp (Workbench, liczone dla profilera)
Ki_i_wb = 7743;  KiDIV_i = 16384;    % Torque/Flux Ki

%% --- Nastawy petli predkosci (Workbench) ---
Kp_w = 800;   KpDIV_w = 64;       % Speed Kp
Ki_w = 250;    KiDIV_w = 1024;     % Speed Ki (w modelu bylo 60, wczesniej tu 250 - sprawdz Workbench)

%% --- Hallotrony (estymator predkosci) ---
Nfifo  = 4;            % bufor usredniania
hallTO = 0.2;          % [s] brak zbocza -> predkosc 0

%% --- Scenariusz testu (nazwy wpisane w bloki modelu) ---
t_end      = 5;        % [s]   czas symulacji (Simulation parameters > Stop time)
t_start    = 0.1;      % [s]   Step: start zadawania predkosci
n_ref      = 1600;     % [rpm SILNIKA] Step: 1600 = 400 rpm wiertla przy 1:4
ramp_up    = 3000;     % [rpm/s] Rate Limiter
ramp_down  = -1000;    % [rpm/s] Rate Limiter
% Obciazenie NA WIERTLE: skok T_step w t_load, potem rampa do T_drill
t_load     = 1;        % [s]   Step1
T_step     = 1;        % [Nm]  Step1: pierwszy kontakt z gruntem
t_ramp     = 1.1;      % [s]   Ramp: poczatek narastania
ramp_slope = 1.84;     % [Nm/s] Ramp: narastanie momentu z glebokoscia
T_drill    = 6.5;      % [Nm]  moment koncowy na wiertle (30 cm)
