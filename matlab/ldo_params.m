function q = ldo_params()
% CONTRACT.md の定数。実装結果に合わせて変更しない。
q.vin = 1.2;            % V
q.vref = 0.45;          % V
q.rtop = 100e3;         % Ohm
q.rbot = 100e3;         % Ohm
q.cout = 10e-9;         % F
q.rload_nominal = 1800; % Ohm (総負荷)
q.rheavy_parallel = 360;% Ohm (1.8 kOhm へ並列追加する値)
q.rload_heavy = 300;    % Ohm (1.8k || 360 の合成。並列追加値ではない)
q.a0 = 200;             % V/V
q.tau_ea = 0.5e-6;      % s
q.gm_pass = 4e-3;       % A/V
q.imax = 5e-3;          % A
q.vctrl_max = 1;        % V
q.pg_high = 0.87;       % V (strict crossing)
q.pg_low = 0.85;        % V (strict crossing)
q.clk_period = 100e-9;  % s
q.pg_stable_cycles = 20;
q.t_stop = 50e-6;       % s
q.scenario_en_on = 2e-6;
q.scenario_load_on = 25e-6;
q.scenario_load_off = 35e-6;
q.solver_fixed_step = 10e-9;
% switch の非理想分。360 Ohm の直列追加値を変えないための小さな値。
q.switch_r_closed = 1e-6;  % Ohm
q.switch_g_open = 1e-12;   % 1/Ohm
q.vref_tol = 1e-9;
end
