function info = build_model(varargin)
% CONTRACT.md の Simscape 閉ループ LDO + pg_cmp 比較器 + Stateflow supervisor を
% MATLAB source から生成し model/generated/ldo_demo.slx へ保存する。
% block path / parameter 名は R2026a 実機で確認したものだけを使う。
p = inputParser;
p.addParameter('FixedStep', []);
p.addParameter('StopTime', []);
p.addParameter('Supervisor', true);
p.addParameter('ModelName', 'ldo_demo');
p.addParameter('Save', true);
p.parse(varargin{:});
o = p.Results;
par = ldo_params();
if isempty(o.FixedStep), o.FixedStep = par.solver_fixed_step; end
if isempty(o.StopTime), o.StopTime = par.t_stop; end

root = fileparts(fileparts(mfilename('fullpath')));
outdir = fullfile(root, 'model', 'generated');
if ~isfolder(outdir), mkdir(outdir); end
u = model_util();
mdl = o.ModelName;
% sflib / Stateflow は Supervisor を作るときだけ load する。Supervisor=false の
% analog-only build では load しない。
for lib = {'fl_lib', 'nesl_utility', 'simulink'}
    load_system(lib{1});
end
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);

% --- top level inputs ---
add_block('simulink/Sources/In1', [mdl '/en'], 'Position', [20 100 50 130]);
add_block('simulink/Sources/In1', [mdl '/load_hi'], 'Position', [20 200 50 230]);
add_block('simulink/Sources/In1', [mdl '/rst'], 'Position', [20 300 50 330]);
% en/load_hi/rst は 0/1 の scenario 入力。外部入力の線形補間を切って step をそのまま与える。
for inName = {'en', 'load_hi', 'rst'}
    set_param([mdl '/' inName{1}], 'Interpolate', 'off');
end

% --- analog part ---
buildAnalog(mdl, u, par);
u.conn(mdl, u.p(mdl, 'en', 'Outport', 1), u.p(mdl, 'Analog LDO', 'Inport', 1));
u.conn(mdl, u.p(mdl, 'load_hi', 'Outport', 1), u.p(mdl, 'Analog LDO', 'Inport', 2));

% --- comparator (pg_cmp) ---
u.addpgcmp(mdl, 'pg_cmp', par, [420 380 520 470]);
u.conn(mdl, u.p(mdl, 'Analog LDO', 'Outport', 1), u.p(mdl, 'pg_cmp', 'Inport', 1));

% --- digital boundary: 0/1 の double を boolean へ明示変換する ---
add_block('simulink/Signal Attributes/Data Type Conversion', [mdl '/en_b'], ...
    'OutDataTypeStr', 'boolean', 'Position', [600 100 640 130]);
add_block('simulink/Signal Attributes/Data Type Conversion', [mdl '/rst_b'], ...
    'OutDataTypeStr', 'boolean', 'Position', [600 300 640 330]);
add_block('simulink/Signal Attributes/Data Type Conversion', [mdl '/pg_cmp_b'], ...
    'OutDataTypeStr', 'boolean', 'Position', [600 380 640 410]);
u.conn(mdl, u.p(mdl, 'en', 'Outport', 1), u.p(mdl, 'en_b', 'Inport', 1));
u.conn(mdl, u.p(mdl, 'rst', 'Outport', 1), u.p(mdl, 'rst_b', 'Inport', 1));
u.conn(mdl, u.p(mdl, 'pg_cmp', 'Outport', 1), u.p(mdl, 'pg_cmp_b', 'Inport', 1));

if o.Supervisor
    chart = add_supervisor(mdl, 'Supervisor', par, [700 100 800 260]);
    assert(~isempty(chart), 'talkrtl:Build', 'supervisor chart missing');
    u.conn(mdl, u.p(mdl, 'rst_b', 'Outport', 1), u.p(mdl, 'Supervisor', 'Inport', 1));
    u.conn(mdl, u.p(mdl, 'en_b', 'Outport', 1), u.p(mdl, 'Supervisor', 'Inport', 2));
    u.conn(mdl, u.p(mdl, 'pg_cmp_b', 'Outport', 1), u.p(mdl, 'Supervisor', 'Inport', 3));
end

% --- top level outputs for logging / CSV ---
outs = {'vout', 'Analog LDO', 1; 'vfb', 'Analog LDO', 2; 'vctrl', 'Analog LDO', 3;
    'ipass', 'Analog LDO', 4; 'pg_cmp', 'pg_cmp', 1};
if o.Supervisor
    outs = [outs; {'pgood', 'Supervisor', 1; 'state', 'Supervisor', 2}];
end
y = 40;
for k = 1:size(outs, 1)
    add_block('simulink/Sinks/Out1', [mdl '/out_' outs{k, 1}], 'Position', [900 y 930 y + 30]);
    u.conn(mdl, u.p(mdl, outs{k, 2}, 'Outport', outs{k, 3}), u.p(mdl, ['out_' outs{k, 1}], 'Inport', 1));
    y = y + 50;
end

% --- logging ---
loglist = {'en', 'en', 1; 'load_hi', 'load_hi', 1; 'rst', 'rst', 1; ...
    'vout', 'Analog LDO', 1; 'vfb', 'Analog LDO', 2; 'vctrl', 'Analog LDO', 3; ...
    'ipass', 'Analog LDO', 4; 'pg_cmp', 'pg_cmp', 1};
if o.Supervisor
    loglist = [loglist; {'pgood', 'Supervisor', 1; 'state', 'Supervisor', 2}];
end
for k = 1:size(loglist, 1)
    u.logsignal(mdl, loglist{k, 2}, loglist{k, 3}, loglist{k, 1});
end

set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'ode4', ...
    'FixedStep', num2str(o.FixedStep), 'StopTime', num2str(o.StopTime), ...
    'SignalLogging', 'on', 'SignalLoggingName', 'logsout', ...
    'SaveOutput', 'off', 'SaveFormat', 'StructureWithTime', ...
    'ReturnWorkspaceOutputs', 'on');

info = struct('model', mdl, 'fixed_step', o.FixedStep, 'stop_time', o.StopTime, ...
    'supervisor', o.Supervisor, 'params', par);
if o.Save
    target = fullfile(outdir, [mdl '.slx']);
    if isfile(target), delete(target); end
    save_system(mdl, target);
    info.saved_to = target;
end
end

function buildAnalog(sys, u, par)
% Analog LDO subsystem: Error Amp / Pass / Rdiv / Cout / Load を識別可能に置く。
analog = [sys '/Analog LDO'];
u.newsub(sys, 'Analog LDO', [120 60 460 560]);
add_block('simulink/Sources/In1', [analog '/en'], 'Position', [20 20 50 50]);
add_block('simulink/Sources/In1', [analog '/load_hi'], 'Position', [20 70 50 100]);
add_block('simulink/Sinks/Out1', [analog '/vout'], 'Position', [1180 40 1210 70]);
add_block('simulink/Sinks/Out1', [analog '/vfb'], 'Position', [1180 100 1210 130]);
add_block('simulink/Sinks/Out1', [analog '/vctrl'], 'Position', [1180 160 1210 190]);
add_block('simulink/Sinks/Out1', [analog '/ipass'], 'Position', [1180 220 1210 250]);

u.addss(analog, 'fl_lib', 'DC Voltage Source', 'Vin', [60 380 120 440]);
set_param([analog '/Vin'], 'v0', num2str(par.vin), 'v0_unit', 'V');
u.addss(analog, 'nesl_utility', 'Solver Configuration', 'SC', [60 500 100 540]);
u.addss(analog, 'fl_lib', 'Electrical Reference', 'Ref', [60 600 100 640]);

buildErrorAmp(analog, u, par);
buildPass(analog, u, par);
buildRdiv(analog, u, par);
buildCout(analog, u, par);
buildLoad(analog, u, par);

% 物理network
u.addss(analog, 'fl_lib', 'Current Sensor', 'Isense_pass', [560 320 620 400]);
u.addss(analog, 'nesl_utility', 'PS-Simulink Converter', 'ipass2sim', [680 420 740 460]);
set_param([analog '/ipass2sim'], 'Unit', 'A');
u.addss(analog, 'fl_lib', 'Voltage Sensor', 'Vsense_vout', [680 300 740 380]);
u.addss(analog, 'nesl_utility', 'PS-Simulink Converter', 'vout2sim', [780 320 840 360]);
set_param([analog '/vout2sim'], 'Unit', 'V');

% 物理networkは名前で結ぶ (subsystem の物理port handleは生成直後に遅延する)
% 分岐は hub port を source 側にして作る。
u.conns(analog, 'Vin/LConn1', u.pname(analog, 'Pass', 'Pvin'));
u.conns(analog, u.pname(analog, 'Pass', 'Pvout'), 'Isense_pass/LConn1');
u.conns(analog, 'Isense_pass/RConn2', u.pname(analog, 'Rdiv', 'Pvout'));
u.conns(analog, u.pname(analog, 'Rdiv', 'Pvout'), u.pname(analog, 'Cout', 'Pvout'));
u.conns(analog, u.pname(analog, 'Rdiv', 'Pvout'), u.pname(analog, 'Load', 'Pvout'));
u.conns(analog, u.pname(analog, 'Rdiv', 'Pvout'), 'Vsense_vout/LConn1');
u.conns(analog, u.pname(analog, 'Rdiv', 'Pgnd'), u.pname(analog, 'Cout', 'Pgnd'));
u.conns(analog, u.pname(analog, 'Rdiv', 'Pgnd'), u.pname(analog, 'Load', 'Pgnd'));
u.conns(analog, u.pname(analog, 'Rdiv', 'Pgnd'), 'Vin/RConn1');
u.conns(analog, u.pname(analog, 'Rdiv', 'Pgnd'), 'Vsense_vout/RConn2');
u.conns(analog, u.pname(analog, 'Rdiv', 'Pgnd'), 'Ref/LConn1');
u.conns(analog, u.pname(analog, 'Rdiv', 'Pgnd'), 'SC/RConn1');
u.conn(analog, u.p(analog, 'Isense_pass', 'RConn', 1), u.p(analog, 'ipass2sim', 'LConn', 1));
u.conn(analog, u.p(analog, 'Vsense_vout', 'RConn', 1), u.p(analog, 'vout2sim', 'LConn', 1));

% Simulink信号
u.conn(analog, u.p(analog, 'Rdiv', 'Outport', 1), u.p(analog, 'Error Amp', 'Inport', 1));
u.conn(analog, u.p(analog, 'Rdiv', 'Outport', 1), u.p(analog, 'vfb', 'Inport', 1));
u.conn(analog, u.p(analog, 'en', 'Outport', 1), u.p(analog, 'Error Amp', 'Inport', 2));
u.conn(analog, u.p(analog, 'Error Amp', 'Outport', 1), u.p(analog, 'Pass', 'Inport', 1));
u.conn(analog, u.p(analog, 'en', 'Outport', 1), u.p(analog, 'Pass', 'Inport', 2));
u.conn(analog, u.p(analog, 'load_hi', 'Outport', 1), u.p(analog, 'Load', 'Inport', 1));
u.conn(analog, u.p(analog, 'Error Amp', 'Outport', 1), u.p(analog, 'vctrl', 'Inport', 1));
u.conn(analog, u.p(analog, 'vout2sim', 'Outport', 1), u.p(analog, 'vout', 'Inport', 1));
u.conn(analog, u.p(analog, 'ipass2sim', 'Outport', 1), u.p(analog, 'ipass', 'Inport', 1));
end

function buildErrorAmp(analog, u, par)
% vc_target = clip(A0*en*(vref-vfb),0,1) の後、d(vctrl)/dt = (vc_target-vctrl)/tau_ea。
% 飽和は一次遅れの前。順序を入れ替えない。
blk = u.newsub(analog, 'Error Amp', [120 40 420 320]);
add_block('simulink/Sources/In1', [blk '/vfb'], 'Position', [20 120 50 150]);
add_block('simulink/Sources/In1', [blk '/en'], 'Position', [20 40 50 70]);
add_block('simulink/Sinks/Out1', [blk '/vctrl'], 'Position', [620 170 650 200]);
u.addconst(blk, 'vref', num2str(par.vref), [20 200 60 240]);
add_block('simulink/Math Operations/Sum', [blk '/ea_sum'], ...
    'Inputs', '+-', 'Position', [120 130 150 190]);
add_block('simulink/Math Operations/Gain', [blk '/ea_gain'], ...
    'Gain', num2str(par.a0), 'Position', [200 140 250 180]);
add_block('simulink/Math Operations/Product', [blk '/en_gate'], ...
    'Inputs', '**', 'Position', [300 120 340 160]);
add_block('simulink/Discontinuities/Saturation', [blk '/vctrl_limit'], ...
    'UpperLimit', num2str(par.vctrl_max), 'LowerLimit', '0', 'Position', [390 130 440 170]);
add_block('simulink/Math Operations/Sum', [blk '/ea_lag_sum'], ...
    'Inputs', '+-', 'Position', [480 150 510 210]);
add_block('simulink/Math Operations/Gain', [blk '/ea_lag_gain'], ...
    'Gain', num2str(1 / par.tau_ea), 'Position', [540 170 580 210]);
add_block('simulink/Continuous/Integrator', [blk '/ea_lag'], ...
    'InitialCondition', '0', 'Position', [610 165 650 215]);
u.conn(blk, u.p(blk, 'vref', 'Outport', 1), u.p(blk, 'ea_sum', 'Inport', 1));
u.conn(blk, u.p(blk, 'vfb', 'Outport', 1), u.p(blk, 'ea_sum', 'Inport', 2));
u.conn(blk, u.p(blk, 'ea_sum', 'Outport', 1), u.p(blk, 'ea_gain', 'Inport', 1));
u.conn(blk, u.p(blk, 'ea_gain', 'Outport', 1), u.p(blk, 'en_gate', 'Inport', 1));
u.conn(blk, u.p(blk, 'en', 'Outport', 1), u.p(blk, 'en_gate', 'Inport', 2));
u.conn(blk, u.p(blk, 'en_gate', 'Outport', 1), u.p(blk, 'vctrl_limit', 'Inport', 1));
u.conn(blk, u.p(blk, 'vctrl_limit', 'Outport', 1), u.p(blk, 'ea_lag_sum', 'Inport', 1));
u.conn(blk, u.p(blk, 'ea_lag', 'Outport', 1), u.p(blk, 'ea_lag_sum', 'Inport', 2));
u.conn(blk, u.p(blk, 'ea_lag_sum', 'Outport', 1), u.p(blk, 'ea_lag_gain', 'Inport', 1));
u.conn(blk, u.p(blk, 'ea_lag_gain', 'Outport', 1), u.p(blk, 'ea_lag', 'Inport', 1));
u.conn(blk, u.p(blk, 'ea_lag', 'Outport', 1), u.p(blk, 'vctrl', 'Inport', 1));
end

function buildPass(analog, u, par)
% ipass = en*clip(gm_pass*vctrl,0,imax)。Controlled Current Source は Vin -> Vout 向き。
blk = u.newsub(analog, 'Pass', [520 40 900 300]);
u.addport(blk, 'Pvin', 1, [20 200 50 230]);
u.addport(blk, 'Pvout', 2, [620 90 650 120]);
add_block('simulink/Sources/In1', [blk '/vctrl'], 'Position', [20 30 50 60]);
add_block('simulink/Sources/In1', [blk '/en'], 'Position', [20 90 50 120]);
add_block('simulink/Math Operations/Gain', [blk '/gm_pass'], ...
    'Gain', num2str(par.gm_pass), 'Position', [90 25 140 65]);
add_block('simulink/Discontinuities/Saturation', [blk '/ipass_limit'], ...
    'UpperLimit', num2str(par.imax), 'LowerLimit', '0', 'Position', [170 25 220 65]);
add_block('simulink/Math Operations/Product', [blk '/en_gate'], ...
    'Inputs', '**', 'Position', [250 35 290 75]);
u.addss(blk, 'nesl_utility', 'Simulink-PS Converter', 'Icmd2PS', [330 40 390 80]);
set_param([blk '/Icmd2PS'], 'Unit', 'A');
u.addss(blk, 'fl_lib', 'Controlled Current Source', 'Ipass', [470 40 530 160]);
u.conn(blk, u.p(blk, 'vctrl', 'Outport', 1), u.p(blk, 'gm_pass', 'Inport', 1));
u.conn(blk, u.p(blk, 'gm_pass', 'Outport', 1), u.p(blk, 'ipass_limit', 'Inport', 1));
u.conn(blk, u.p(blk, 'ipass_limit', 'Outport', 1), u.p(blk, 'en_gate', 'Inport', 1));
u.conn(blk, u.p(blk, 'en', 'Outport', 1), u.p(blk, 'en_gate', 'Inport', 2));
u.conn(blk, u.p(blk, 'en_gate', 'Outport', 1), u.p(blk, 'Icmd2PS', 'Inport', 1));
u.conn(blk, u.p(blk, 'Icmd2PS', 'RConn', 1), u.p(blk, 'Ipass', 'RConn', 1));
u.conn(blk, u.p(blk, 'Pvin', 'RConn', 1), u.p(blk, 'Ipass', 'RConn', 2));
u.conn(blk, u.p(blk, 'Pvout', 'RConn', 1), u.p(blk, 'Ipass', 'LConn', 1));
end

function buildRdiv(analog, u, par)
% Rdiv: 100k + 100k。vfb を Voltage Sensor で観測する。
blk = u.newsub(analog, 'Rdiv', [520 340 900 560]);
u.addport(blk, 'Pvout', 1, [20 30 50 60]);
u.addport(blk, 'Pgnd', 2, [20 220 50 250]);
u.addss(blk, 'fl_lib', 'Resistor', 'Rtop', [160 60 220 120]);
set_param([blk '/Rtop'], 'R', num2str(par.rtop), 'R_unit', 'Ohm');
u.addss(blk, 'fl_lib', 'Resistor', 'Rbot', [160 180 220 240]);
set_param([blk '/Rbot'], 'R', num2str(par.rbot), 'R_unit', 'Ohm');
u.addss(blk, 'fl_lib', 'Voltage Sensor', 'Vsense_vfb', [300 140 360 220]);
u.addss(blk, 'nesl_utility', 'PS-Simulink Converter', 'vfb2sim', [420 160 480 200]);
set_param([blk '/vfb2sim'], 'Unit', 'V');
add_block('simulink/Sinks/Out1', [blk '/vfb'], 'Position', [560 170 590 200]);
n_vfb = u.p(blk, 'Rtop', 'RConn', 1);
u.conn(blk, u.p(blk, 'Pvout', 'RConn', 1), u.p(blk, 'Rtop', 'LConn', 1));
u.conn(blk, n_vfb, u.p(blk, 'Rbot', 'LConn', 1));
u.conn(blk, n_vfb, u.p(blk, 'Vsense_vfb', 'LConn', 1));
u.conn(blk, u.p(blk, 'Rbot', 'RConn', 1), u.p(blk, 'Pgnd', 'RConn', 1));
u.conn(blk, u.p(blk, 'Vsense_vfb', 'RConn', 2), u.p(blk, 'Pgnd', 'RConn', 1));
u.conn(blk, u.p(blk, 'Vsense_vfb', 'RConn', 1), u.p(blk, 'vfb2sim', 'LConn', 1));
u.conn(blk, u.p(blk, 'vfb2sim', 'Outport', 1), u.p(blk, 'vfb', 'Inport', 1));
end

function buildCout(analog, u, par)
% Cout: 10 nF を vout と gnd の間に置く。
blk = u.newsub(analog, 'Cout', [920 340 1120 500]);
u.addport(blk, 'Pvout', 1, [20 40 50 70]);
u.addport(blk, 'Pgnd', 2, [20 140 50 170]);
u.addss(blk, 'fl_lib', 'Capacitor', 'Cout', [200 80 260 160]);
set_param([blk '/Cout'], 'c', num2str(par.cout * 1e9), 'c_unit', 'nF');
u.conn(blk, u.p(blk, 'Pvout', 'RConn', 1), u.p(blk, 'Cout', 'LConn', 1));
u.conn(blk, u.p(blk, 'Cout', 'RConn', 1), u.p(blk, 'Pgnd', 'RConn', 1));
end

function buildLoad(analog, u, par)
% Load: 1.8 kOhm 固定 + (360 Ohm 直列 switch) の並列。heavy の総抵抗は 300 Ohm。
% 300 Ohm を直接並列追加しない。
blk = u.newsub(analog, 'Load', [920 40 1180 300]);
u.addport(blk, 'Pvout', 1, [20 240 50 270]);
u.addport(blk, 'Pgnd', 2, [20 300 50 330]);
add_block('simulink/Sources/In1', [blk '/load_hi'], 'Position', [20 40 50 70]);
u.addss(blk, 'fl_lib', 'Resistor', 'Rload', [180 40 240 100]);
set_param([blk '/Rload'], 'R', num2str(par.rload_nominal), 'R_unit', 'Ohm');
u.addss(blk, 'fl_lib', 'Resistor', 'Rheavy', [180 150 240 210]);
set_param([blk '/Rheavy'], 'R', num2str(par.rheavy_parallel), 'R_unit', 'Ohm');
u.addss(blk, 'fl_lib', 'Switch', 'Sw_heavy', [320 140 380 220]);
set_param([blk '/Sw_heavy'], 'R_closed', num2str(par.switch_r_closed), ...
    'R_closed_unit', 'Ohm', 'G_open', num2str(par.switch_g_open), ...
    'G_open_unit', '1/Ohm', 'Threshold', '0.5');
u.addss(blk, 'nesl_utility', 'Simulink-PS Converter', 'hi2ps', [80 130 140 170]);
set_param([blk '/hi2ps'], 'Unit', '1');
u.conn(blk, u.p(blk, 'load_hi', 'Outport', 1), u.p(blk, 'hi2ps', 'Inport', 1));
u.conn(blk, u.p(blk, 'hi2ps', 'RConn', 1), u.p(blk, 'Sw_heavy', 'RConn', 1));
u.conn(blk, u.p(blk, 'Pvout', 'RConn', 1), u.p(blk, 'Rload', 'LConn', 1));
u.conn(blk, u.p(blk, 'Rload', 'RConn', 1), u.p(blk, 'Pgnd', 'RConn', 1));
u.conn(blk, u.p(blk, 'Pvout', 'RConn', 1), u.p(blk, 'Rheavy', 'LConn', 1));
u.conn(blk, u.p(blk, 'Rheavy', 'RConn', 1), u.p(blk, 'Sw_heavy', 'LConn', 1));
u.conn(blk, u.p(blk, 'Sw_heavy', 'RConn', 2), u.p(blk, 'Pgnd', 'RConn', 1));
end
