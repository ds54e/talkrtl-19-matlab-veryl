function result = run_reference()
io = reference_io();
par = ldo_params();
paths = demo_paths();
resdir = paths.reference_dir;
sdir = paths.sdi_dir;

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

io.csv(fullfile(resdir, 'analog.csv'), ...
    {'t_s', 'en', 'load_hi', 'vout', 'vfb', 'vctrl', 'ipass', 'pg_cmp'}, ...
    {S.vout.Time, pickconst(S.en, S.vout.Time), pickconst(S.load_hi, S.vout.Time), ...
    S.vout.Data, pickconst(S.vfb, S.vout.Time), pickconst(S.vctrl, S.vout.Time), ...
    pickconst(S.ipass, S.vout.Time), pickconst(S.pg_cmp, S.vout.Time)});

n = numel(S.pgood.Data) - 1;
dig = struct('tick', (0:n)', 'time_ns', (0:n)' * par.clk_period * 1e9, ...
    'rst', round(pickconst(S.rst, S.pgood.Time)), 'en', round(pickconst(S.en, S.pgood.Time)), ...
    'pg_cmp', round(pickconst(S.pg_cmp, S.pgood.Time)), ...
    'state', round(S.state.Data), 'pgood', round(S.pgood.Data));
dig.state_name = arrayfun(@(s) state_name(s), dig.state, 'UniformOutput', false);
io.csv(fullfile(resdir, 'digital.csv'), ...
    {'tick', 'time_ns', 'rst', 'en', 'pg_cmp', 'state', 'state_name', 'pgood'}, ...
    {dig.tick, dig.time_ns, dig.rst, dig.en, dig.pg_cmp, dig.state, dig.state_name, dig.pgood});

if ~isfolder(sdir), mkdir(sdir); end
sdiPath = fullfile(sdir, 'reference.mldatx');
sdi = struct('path', sdiPath, 'saved', false);
try
    Simulink.sdi.save(sdiPath);
    sdi.saved = isfile(sdiPath);
catch ME
    sdi.error_identifier = ME.identifier;
    sdi.error_message = ME.message;
end

checks = reference_checks(S, dig, par);
result = struct('phase', 'reference', 'pass', checks.pass && sdi.saved, ...
    'checks', checks, 'sdi', sdi);
fprintf('reference: checks=%d/%d SDI=%s : %s\n', ...
    checks.passed, checks.total, tf(sdi.saved), tf(result.pass));
end

function c = reference_checks(S, dig, par)
v = S.vout;
c.checks = {};

expected_analog = round(par.t_stop / par.solver_fixed_step) + 1;
expected_ticks = round(par.t_stop / par.clk_period) + 1;
c.checks{end + 1} = ci('sample count', ...
    numel(v.Data) == expected_analog && numel(dig.tick) == expected_ticks);

finite_ok = all(isfinite(v.Data)) && all(isfinite(S.vctrl.Data)) && all(isfinite(S.ipass.Data));
c.checks{end + 1} = ci('analog finite', finite_ok);

pre = max(abs(v.Data(v.Time < par.scenario_en_on)));
normal = mean(v.Data(v.Time >= 15e-6 & v.Time <= 24e-6));
heavy = min(v.Data(v.Time >= par.scenario_load_on & v.Time <= par.scenario_load_off));
recovered = min(v.Data(v.Time >= 32e-6 & v.Time <= 34e-6));
c.checks{end + 1} = ci('analog scenario', ...
    pre < 1e-3 && normal >= 0.88 && normal <= 0.92 && ...
    heavy < par.pg_low && recovered > par.pg_high);

tr = transitions(S.pg_cmp);
c.checks{end + 1} = ci('pg_cmp rise/fall/rise', ...
    numel(tr.dir) == 3 && isequal(tr.dir, [1 -1 1]));

d = digital_events(dig);
c.checks{end + 1} = ci('PGOOD qualification', ...
    d.first_ok && d.rehigh_ok && d.drop_reassert);

c.passed = sum(cellfun(@(x) x.ok, c.checks));
c.total = numel(c.checks);
c.pass = all(cellfun(@(x) x.ok, c.checks));
end

function d = digital_events(dig)
pg = dig.pg_cmp(:);
good = dig.pgood(:);
n = numel(pg);
d = struct('first_ok', false, 'rehigh_ok', false, 'drop_reassert', false);

i0 = find(pg == 1, 1);
if isempty(i0), return; end
d.first_ok = i0 + 20 <= n && good(i0 + 19) == 0 && good(i0 + 20) == 1;

fi = find(pg(i0 + 1:end) == 0, 1);
if isempty(fi), return; end
fi = i0 + fi;
hi = find(pg(fi + 1:end) == 1, 1);
if isempty(hi), return; end
hi = fi + hi;
d.rehigh_ok = hi + 20 <= n && good(hi + 19) == 0 && good(hi + 20) == 1;

first = find(good == 1, 1);
if isempty(first), return; end
drop = find(good(first + 1:end) == 0, 1);
if isempty(drop), return; end
d.drop_reassert = any(good(first + drop + 1:end) == 1);
end

function v = pickconst(ts, times)
if all(ts.Data == ts.Data(1))
    v = repmat(ts.Data(1), numel(times), 1);
else
    idx = arrayfun(@(tq) find(ts.Time <= tq + 1e-15, 1, 'last'), times);
    v = ts.Data(idx);
end
end

function tr = transitions(ts)
d = diff(ts.Data);
idx = find(d ~= 0);
tr.dir = sign(d(idx))';
tr.dir = tr.dir(:)';
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
