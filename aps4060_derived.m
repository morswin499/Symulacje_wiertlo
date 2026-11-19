% =====================================================================
%  APS 4060S + B-G431B-ESC1  —  OBLICZENIA (nie trzeba edytowac)
%  Wymaga wczesniejszego run("aps4060_params.m")
% =====================================================================

%% --- Wybor Rs, Ld, Lq ---
% L miedzyfazowe w funkcji kata: L_LL = (Ld+Lq) + (Ld-Lq)*cos(2*phi).
% 3 pary = 3 probki co 120 deg (w 2*phi) -> srednia = Ld+Lq, amplituda = Lq-Ld
Rs_pom = R_LL_meas/2 * (1 + alpha_cu*(T_wind - T_meas));   % [Ohm] faza, przeliczona na T_wind
L_sr   = mean(L_LL_3);
L_amp  = sqrt(2/3*sum((L_LL_3 - L_sr).^2));
switch src
  case 'pomiar',   Rs = Rs_pom;   Ld = (L_sr - L_amp)/2;  Lq = (L_sr + L_amp)/2;
  case 'profiler', Rs = Rs_prof;  Ld = Ls_prof;           Lq = Ls_prof;
  otherwise, error('src musi byc ''pomiar'' albo ''profiler''');
end
Ls = (Ld + Lq)/2;      % do nastaw: MCSDK (i C-Script) ma te same Kp, Ki dla osi d i q

%% --- Model silnika do bloku PMSM ---
psi_m = Ke*sqrt(2)/sqrt(3) / (1000*2*pi/60);   % [Vs/rad mech]
psi   = psi_m/p;                               % [Vs]  -> blok PMSM
Kt    = 1.5*psi_m;                             % [Nm/A pk]
% Bezwladnosc sprowadzona na wal silnika (do oceny petli i rezonansu):
J1 = J_rotor;                           % strona silnika
J2 = J_C/N_gear^2;                      % wiertlo widziane z silnika
if coupling_after_gear
  Kr = K_c/N_gear^2;                    % sztywnosc sprzegla widziana z silnika
  sD = N_gear^2;                        % przeliczenie D na miejsce montazu
else
  Kr = K_c;  sD = 1;
end
J = J1 + J2;                            % calkowite
J_pmsm = J_rotor;                       % blok PMSM; wiertlo w bloku Inertia "J_wiertla" za Gear

%% --- Sprzeglo: tlumienie i rezonans ---
J_eq  = J1*J2/(J1 + J2);
f_res = sqrt(Kr/J_eq)/(2*pi);           % [Hz] rezonans skretny
D_c   = 2*zeta_c*sqrt(Kr*J_eq)*sD;      % [N m s/rad] -> Rotational Damper

%% --- Obciazenie ---
% Gear w PLECS jest idealny -> straty przekladni = obciazenie podzielone przez eta
T_out  = T_drill/eta_gear;              % [Nm] koncowy moment w Torque2
T_load = T_drill/(N_gear*eta_gear);     % [Nm] to samo na wale silnika
T_step_out     = T_step/eta_gear;              % -> Step1 After
ramp_slope_out = ramp_slope/eta_gear;          % -> Ramp slope
T_ramp_out     = (T_drill - T_step)/eta_gear;  % -> Ramp XFinal
t_ramp_end     = t_ramp + (T_drill - T_step)/ramp_slope;
if t_ramp_end > t_end
  fprintf('UWAGA: rampa obciazenia konczy sie w %.2f s, po koncu symulacji (%.2f s)\n', t_ramp_end, t_end);
end

%% --- Skalowanie MCSDK ---
Kcur = 65536*Rsh*Gamp/Vref;    % s16A / A
Kvol = sqrt(3)*32768/Vbus;     % s16V / V (amplituda fazowa)
Kspd = 10/(2*pi);              % 0.1 Hz / (rad/s)
Ts_c = 1/fpwm;  Ts_s = 1/fspd;
Iq_lim_dig = round(Imax*Kcur);
kV = Kcur/Kvol;                % [V/A] na 1 jednostke cyfrowa nastawy (Kp_ph = Kp/DIV * kV)

%% --- Nastawy petli pradu wg gain_mode_i ---
switch gain_mode_i
  case 'workbench'
    Kp_i = Kp_i_wb;  Ki_i = Ki_i_wb;
  case 'przeskaluj'            % Kp ~ L, Ki ~ R, oba ~ 1/Vbus -> pasmo i zero jak w Workbench
    Kp_i = round(Kp_i_wb*Ls/Ls_prof*Vbus_wb/Vbus);
    Ki_i = round(Ki_i_wb*Rs/Rs_prof*Vbus_wb/Vbus);
  case 'projekt'
    Kp_i = round(Ls*wc_i/kV*KpDIV_i);
    Ki_i = round(Rs*wc_i/(fpwm*kV)*KiDIV_i);
  otherwise, error('gain_mode_i: ''workbench'' / ''przeskaluj'' / ''projekt''');
end

%% --- Kontrola nastaw ---
divs = [KpDIV_i KiDIV_i KpDIV_w KiDIV_w];
if any(mod(log2(divs),1) ~= 0)
  error('Dzielniki musza byc potegami 2');
end
if any([Kp_i Ki_i Kp_w Ki_w] > 32767)
  error('Nastawa > 32767 (int16) - zwieksz dzielnik');
end

%% --- Wektor parametrow C-Script (kolejnosc jak w kodzie!) ---
cs_par = [Kcur, Ts_c, p, Kp_i, Ki_i, log2(KpDIV_i), log2(KiDIV_i), ...
          Kp_w, Ki_w, log2(KpDIV_w), log2(KiDIV_w), Iq_lim_dig, ...
          round(fpwm/fspd), Nfifo, maxmod, hallTO];

%% --- Wersja blokowa (Discrete PID w jednostkach fizycznych) ---
hall_par = [Ts_c, p, Nfifo, hallTO];   % -> C-Script hall_estimator_cscript.c
V_lim    = maxmod*Vbus/sqrt(3);         % [V] limit |Vdq| (amplituda fazowa)
Iq_lim   = Imax;                        % [A] limit wyjscia petli predkosci
ADC_lsb  = 16/Kcur;                     % [A] krok pomiaru pradu (12-bit ADC)

%% --- Interpretacja fizyczna nastaw ---
Kp_i_ph = Kp_i/KpDIV_i * kV;                   % [V/A]
Ki_i_ph = Ki_i/KiDIV_i * fpwm * kV;            % [V/(A s)]
wc      = Kp_i_ph/Ls;                          % pasmo petli pradu
wc_wb   = Kp_i_wb/KpDIV_i*kV/Ls;               % pasmo nastaw Workbench na AKTYWNYM silniku
Kp_w_ph = Kp_w/KpDIV_w * Kspd/Kcur;            % [A/(rad/s)]
Ki_w_ph = Ki_w/KiDIV_w * fspd * Kspd/Kcur;
ws      = Kp_w_ph*Kt/J;                        % pasmo petli predkosci

%% --- Granice napedu ---
Vmax  = maxmod*Vbus/sqrt(3);
n_max = Vmax/psi_m*60/(2*pi);                  % bez obciazenia
a = psi_m^2 + (p*Lq*Imax)^2;  b = 2*psi_m*Rs*Imax;  c = (Rs*Imax)^2 - Vmax^2;
n_corner = (-b + sqrt(b^2 - 4*a*c))/(2*a)*60/(2*pi);   % pelny moment do tej predkosci
T_max = Kt*Imax;
Pcu_max = 1.5*Rs*Imax^2;                       % [W] straty w miedzi przy Imax (amplituda)

%% --- Podsumowanie ---
fprintf('\n=== APS 4060S | Vbus %.2f V | PWM %.0f kHz ===\n', Vbus, fpwm/1e3);
fprintf('Parametry: %s  Rs = %.4f Ohm, Ld = %.3f, Lq = %.3f mH (srednio %.3f)  [profiler %.3f Ohm, %.3f mH]\n', ...
        src, Rs, Ld*1e3, Lq*1e3, Ls*1e3, Rs_prof, Ls_prof*1e3);
if strcmp(src,'pomiar')
  fprintf('           Rs przy %.0f degC (pomiar %.0f degC), R_LL = %.4f Ohm\n', T_wind, T_meas, R_LL_meas);
end
fprintf('Nastawy pradu [%s]: Kp = %d/%d, Ki = %d/%d  -> wpisz do MC Workbench\n', ...
        gain_mode_i, Kp_i, KpDIV_i, Ki_i, KiDIV_i);
if ~strcmp(gain_mode_i,'workbench')
  fprintf('  (stare z Workbench %d/%d, %d/%d dalyby na tym silniku wc = %.0f rad/s)\n', ...
          Kp_i_wb, KpDIV_i, Ki_i_wb, KiDIV_i, wc_wb);
end
PM_i = 90 - wc*1.5*Ts_c*180/pi;   % zapas fazy: idealne 90 deg minus opoznienie ~1.5 Ts
fprintf('  zapas fazy petli pradu ~%.0f deg (opoznienie 1.5 Ts)\n', PM_i);
if PM_i < 45
  fprintf('  UWAGA: zapas fazy < 45 deg - zmniejsz wc albo zwieksz fpwm\n');
end
fprintf('PMSM: psi = %.3g Vs, J = %.3g kg m^2 (wirnik %.0f%%)\n', psi, J, 100*J_rotor/J);
fprintf('Petla pradu : wc = %.0f rad/s (%.0f Hz), zero %.0f rad/s (R/L = %.0f)\n', ...
        wc, wc/2/pi, Ki_i_ph/Kp_i_ph, Rs/Ls);
fprintf('Petla pred. : ws = %.0f rad/s (%.1f Hz), zero %.1f rad/s\n', ws, ws/2/pi, Ki_w_ph/Kp_w_ph);
fprintf('Silnik : T_max %.2f Nm do %.0f rpm, n_max %.0f rpm, Pcu(Imax) %.0f W\n', ...
        T_max, n_corner, n_max, Pcu_max);
fprintf('Wiertlo: T_max %.2f Nm do %.0f rpm, n_max %.0f rpm\n', ...
        T_max*N_gear*eta_gear, n_corner/N_gear, n_max/N_gear);
fprintf('Sprzeglo: K = %.3g Nm/rad, D = %.3g Nm s/rad, rezonans %.0f Hz', K_c, D_c, f_res);
fprintf(' (petla pred. %.0f Hz, pradu %.0f Hz)\n', ws/2/pi, wc/2/pi);
if f_res < 5*ws/2/pi
  fprintf('  UWAGA: rezonans blisko pasma petli predkosci - ryzyko oscylacji!\n');
end
fprintf('Test: n_ref %.0f rpm (wiertlo %.0f rpm), Torque2 = T_out %.3f Nm (na silniku %.3f Nm)\n', ...
        n_ref, n_ref/N_gear, T_out, T_load);
fprintf('Obciazenie: %.2f Nm w %.2f s, rampa %.2f Nm/s od %.2f s do %.2f Nm w %.2f s (z eta)\n', ...
        T_step_out, t_load, ramp_slope_out, t_ramp, T_out, t_ramp_end);
fprintf('Bezwladnosc: PMSM %.3g, blok J_wiertla %.3g (na silniku %.3g = %.0f%% wirnika) kg m^2\n', ...
        J_pmsm, J_C, J_C/N_gear^2, 100*J_C/N_gear^2/J_rotor);
if T_load > T_max
  fprintf('UWAGA: obciazenie na silniku %.2f Nm > T_max %.2f Nm (Imax %.0f A) - wiertlo stanie\n', ...
          T_load, T_max, Imax);
end
fprintf('\n');
