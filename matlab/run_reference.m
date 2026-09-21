function result = run_reference()
% 公開 reference flow の入口。nominal の Simscape 閉ループ LDO + Stateflow supervisor を
% 1 回だけ実行し、results/generated/reference/ へ analog/digital CSV を、results/generated/sdi/
% へ SDI session を保存する。同じ nominal run の実測値に対して軽量な健全性チェックを行い、
% SDI session の保存と併せて pass を返す。追加の開発用シミュレーションは実行しない。
io = reference_io();
par = ldo_params();
resdir = fullfile(io.root(), 'results', 'generated', 'reference');
sdir = fullfile(io.root(), 'results', 'generated', 'sdi');

% --- nominal run: reference model を 1 回だけ流し、SDI session と data export に使う ---
fprintf('=== reference model: nominal run ===\n');
Simulink.sdi.clear();
info = build_model('Supervisor', true, 'FixedStep', par.solver_fixed_step, ...
    'StopTime', par.t_stop, 'Save', true);
mdl = info.model;
t = (0:par.solver_fixed_step:par.t_stop)';
en = double(t >= par.scenario_en_on);
load_hi = double(t >= par.scenario_load_on & t < par.scenario_load_off);
out = io.runwith(mdl, t, [en, load_hi, zeros(size(t))]);
S = io.logged(out, {'vout', 'vfb', 'vctrl', 'ipass', 'pg_cmp', 'pgood', 'state', ...
    'en', 'load_hi', 'rst'});

% analog CSV (solver の時間格子)
io.csv(fullfile(resdir, 'analog.csv'), ...
    {'t_s', 'en', 'load_hi', 'vout', 'vfb', 'vctrl', 'ipass', 'pg_cmp'}, ...
    {S.vout.Time, pickconst(S.en, S.vout.Time), pickconst(S.load_hi, S.vout.Time), ...
    S.vout.Data, pickconst(S.vfb, S.vout.Time), pickconst(S.vctrl, S.vout.Time), ...
    pickconst(S.ipass, S.vout.Time), pickconst(S.pg_cmp, S.vout.Time)});

% digital CSV (100 ns tick の処理後出力)。logic を補間しない。
step = S.pg_cmp.Time(2) - S.pg_cmp.Time(1);
ratio = round(par.clk_period / step);
n = numel(S.pgood.Data) - 1;
dig = struct('tick', (0:n)', 'time_ns', (0:n)' * par.clk_period * 1e9, ...
    'rst', round(pickconst(S.rst, S.pgood.Time)), 'en', round(pickconst(S.en, S.pgood.Time)), ...
    'pg_cmp', round(pickconst(S.pg_cmp, S.pgood.Time)), ...
    'state', round(S.state.Data), 'pgood', round(S.pgood.Data));
dig.state_name = arrayfun(@(s) state_name(s), dig.state, 'UniformOutput', false);
io.csv(fullfile(resdir, 'digital.csv'), ...
    {'tick', 'time_ns', 'rst', 'en', 'pg_cmp', 'state', 'state_name', 'pgood'}, ...
    {dig.tick, dig.time_ns, dig.rst, dig.en, dig.pg_cmp, dig.state, dig.state_name, dig.pgood});

% SDI session
if ~isfolder(sdir), mkdir(sdir); end
sdiPath = fullfile(sdir, 'reference.mldatx');
sdi = struct('path', sdiPath, 'saved', false);
try
    Simulink.sdi.save(sdiPath);
    sdi.saved = isfile(sdiPath);
    sdi.bytes = dir(sdiPath).bytes;
catch ME
    sdi.error_identifier = ME.identifier;
    sdi.error_message = ME.message;
end
sdi.run_count = numel(Simulink.sdi.getAllRunIDs());

% --- nominal run の実測値に対する軽量チェック ---
nchk = nominal_checks(S, dig, par);

result = struct('phase', 'reference', 'pass', nchk.pass && sdi.saved, ...
    'checks', nchk, 'sdi', sdi);

fprintf('reference nominal: checks=%d/%d SDI=%s : %s\n', nchk.passed, nchk.total, ...
    tf(sdi.saved), tf(result.pass));
end

function c = nominal_checks(S, dig, par)
% nominal run の実測値だけを使う軽量な健全性チェック。追加の sim は行わない。
v = S.vout;
c = struct();
c.checks = {};

% --- 時間格子 / サンプル数 ---
expected_analog = round(par.t_stop / par.solver_fixed_step) + 1;
expected_ticks = round(par.t_stop / par.clk_period) + 1;
c.analog_samples = numel(v.Data);
c.digital_ticks = numel(dig.tick);
c.checks{end + 1} = ci('analog サンプル数 = t_stop/step + 1', numel(v.Data) == expected_analog);
c.checks{end + 1} = ci('digital tick 数が 501 (t_stop/clk + 1)', ...
    numel(dig.tick) == expected_ticks && numel(dig.tick) == 501);

% --- 有限性 ---
c.nan_or_inf = any(~isfinite(v.Data)) || any(~isfinite(S.vctrl.Data)) || any(~isfinite(S.ipass.Data));
c.checks{end + 1} = ci('vout/vctrl/ipass に NaN/Inf なし', ~c.nan_or_inf);

% --- enable 前は約 0 V ---
c.vout_before_enable_max_abs_V = max(abs(v.Data(v.Time < par.scenario_en_on)));
c.checks{end + 1} = ci('enable 前 vout 約0 V (|v|<1 mV)', c.vout_before_enable_max_abs_V < 1e-3);

% --- 定常窓 15..24 us ---
w1 = window(v, 15e-6, 24e-6);
c.vout_win_15_24_mean_V = w1.mean;
c.vout_win_15_24_pp_V = w1.pp;
c.checks{end + 1} = ci('15..24us vout 0.88..0.92 V', w1.mean >= 0.88 && w1.mean <= 0.92);
c.checks{end + 1} = ci('15..24us peak-to-peak <1 mV', w1.pp < 1e-3);

% --- heavy 過渡 ---
selh = v.Time >= par.scenario_load_on & v.Time <= par.scenario_load_off;
c.vout_heavy_min_V = min(v.Data(selh));
c.checks{end + 1} = ci('heavy 過渡で vout が 0.85 V 未満へ', c.vout_heavy_min_V < par.pg_low);

% --- 復帰窓 32..34 us ---
w2 = window(v, 32e-6, 34e-6);
c.vout_win_32_34_min_V = w2.min;
c.vout_win_32_34_pp_V = w2.pp;
c.checks{end + 1} = ci('32..34us vout >0.87 V', w2.min > par.pg_high);
c.checks{end + 1} = ci('32..34us peak-to-peak <1 mV', w2.pp < 1e-3);

% --- 全期間の上下限 ---
c.vout_min_V = min(v.Data);
c.vout_max_V = max(v.Data);
c.checks{end + 1} = ci('vout が -1 uV を下回らない', c.vout_min_V >= -1e-6);
c.checks{end + 1} = ci('vout < 1.1 V', c.vout_max_V < 1.1);

% --- pg_cmp の nominal rise/fall/rise ---
pt = logical_transitions(S.pg_cmp, 'analog_t_s');
c.pg_cmp_transitions = numel(pt.time);
c.checks{end + 1} = ci('pg_cmp 遷移が rise/fall/rise', ...
    numel(pt.time) == 3 && isequal(pt.dir, [1 -1 1]));

% --- digital trace から導出した PGOOD 計時契約 ---
d = digital_events(dig);
c.pgood_first_rise_s = d.pgood_first_rise_s;
c.pg_cmp_k0_tick = d.k0_tick;
c.pg_cmp_fall_tick = d.fall_tick;
c.pg_cmp_rehigh_tick = d.rehigh_tick;
c.checks{end + 1} = ci('最初の pgood assert が 10 us より前', ...
    ~isnan(d.pgood_first_rise_s) && d.pgood_first_rise_s < 10e-6);
c.checks{end + 1} = ci('最初の連続 High: k0+19 で pgood=0 / k0+20 で 1', d.k0_ok);
c.checks{end + 1} = ci('heavy Low 後の再 High でも同じ +19/+20 則', d.rehigh_ok);
c.checks{end + 1} = ci('pgood が heavy 過渡で Low → 再 assert', d.pgood_drop_reassert);

c.passed = sum(cellfun(@(x) x.ok, c.checks));
c.total = numel(c.checks);
c.pass = all(cellfun(@(x) x.ok, c.checks));
end

function d = digital_events(dig)
% 生成した digital trace から最初の High (k0)、負荷起因の Low、再 High を導出し、
% supervisor の 20 区間契約 (+19 で 0 / +20 で 1) を検査する。tick を決め打ちしない。
pg = dig.pg_cmp(:);
good = dig.pgood(:);
n = numel(pg);
d = struct('k0_tick', NaN, 'fall_tick', NaN, 'rehigh_tick', NaN, ...
    'k0_ok', false, 'rehigh_ok', false, 'pgood_drop_reassert', false, ...
    'pgood_first_rise_s', NaN);

first = find(good == 1, 1);
if ~isempty(first), d.pgood_first_rise_s = dig.time_ns(first) * 1e-9; end

i0 = find(pg == 1, 1);                 % 最初の High 観測 (連続 High の先頭)
if isempty(i0), return; end
d.k0_tick = i0 - 1;
d.k0_ok = i0 + 20 <= n && good(i0 + 19) == 0 && good(i0 + 20) == 1;

fi = find(pg(i0 + 1:end) == 0, 1);      % 最初の 1->0 (負荷起因の Low)
if isempty(fi), return; end
fi = i0 + fi;
d.fall_tick = fi - 1;
hi = find(pg(fi + 1:end) == 1, 1);      % その後の再 High
if isempty(hi), return; end
hi = fi + hi;
d.rehigh_tick = hi - 1;
d.rehigh_ok = hi + 20 <= n && good(hi + 19) == 0 && good(hi + 20) == 1;

if ~isempty(first)
    drop = find(good(first + 1:end) == 0, 1);
    if ~isempty(drop)
        reassert = find(good(first + drop + 1:end) == 1, 1);
        d.pgood_drop_reassert = ~isempty(reassert);
    end
end
end

function v = pickconst(ts, times)
if all(ts.Data == ts.Data(1))
    v = repmat(ts.Data(1), numel(times), 1);
else
    idx = arrayfun(@(tq) find(ts.Time <= tq + 1e-15, 1, 'last'), times);
    v = ts.Data(idx);
end
end

function tr = logical_transitions(ts, mode, clk)
d = diff(ts.Data);
idx = find(d ~= 0);
tr.time = ts.Time(idx + 1);
tr.dir = sign(d(idx))';
tr.dir = tr.dir(:)';
if nargin >= 3
    tr.tick = round(tr.time / clk);
else
    tr.tick = nan(size(tr.time));
end
end

function w = window(ts, t0, t1)
sel = ts.Time >= t0 & ts.Time <= t1;
w.min = min(ts.Data(sel));
w.max = max(ts.Data(sel));
w.mean = mean(ts.Data(sel));
w.pp = w.max - w.min;
end

function n = state_name(s)
switch s
    case 0, n = 'OFF';
    case 1, n = 'WAIT';
    case 2, n = 'ON';
    otherwise, n = 'UNKNOWN';
end
end

function c = ci(name, ok)
c = struct('name', name, 'ok', logical(ok));
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
