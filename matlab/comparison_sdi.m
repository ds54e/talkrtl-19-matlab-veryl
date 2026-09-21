function info = comparison_sdi(io)
% comparison SDI session を作る。
%
% 1. reference session (results/generated/sdi/reference.mldatx) を load する
% 2. その reference run を保持したまま、Verilator の結果を新しい run として追加する
% 3. analog は linear、logic/discrete は zero-order hold にする
% 4. 4x1 の比較 view を programmatic に構成する
% 5. results/generated/sdi/comparison.mldatx へ save する
%
% API は R2026a で実測して確認したものだけを使う (記憶で決め打ちしない)。
%   Simulink.sdi.createRun(name,'namevalue',sourceNames,sigValues) -> runID
%   Simulink.sdi.Run.Name / Simulink.sdi.Signal.Name / .InterpMethod は settable
%   Simulink.sdi.Signal.plotOnSubPlot(r,c,true)
%   Simulink.sdi.setSubPlotLayout(4,1) は save/load をまたいで残る
s = io.paths();

REFERENCE_RUN_NAME = 'Reference: Simscape + Stateflow';
IMPLEMENTATION_RUN_NAME = 'Implementation: Verilator RNM + Veryl';
MAIN = {'vout', 'pg_cmp', 'pgood', 'state'};
EXTRA = {'en', 'load_hi', 'vctrl'};
ZOH = {'en', 'load_hi', 'pg_cmp', 'pgood', 'state', 'rst'};

assert(isfile(s.reference_session), 'talkrtl:Comparison', ...
    ['reference SDI session がありません: %s\n' ...
     '再生成: bash tools/matlab-batch "addpath(''matlab''); run_reference"'], s.reference_session);
assert(isfile(fullfile(s.verilator_dir, 'rnm_nominal_full.csv')), 'talkrtl:Comparison', ...
    'Verilator 出力がありません: %s (sim/run_verilator.sh が生成する)', s.verilator_dir);

% ---- 1. reference run を load して名前を明示する --------------------------
Simulink.sdi.clear();
loaded = Simulink.sdi.load(s.reference_session);
ids = Simulink.sdi.getAllRunIDs();
assert(numel(ids) >= 1, 'talkrtl:Comparison', 'reference session に run がありません: %s', s.reference_session);
ref_run = Simulink.sdi.getRun(ids(1));
ref_run.Name = REFERENCE_RUN_NAME;

% ---- 2. implementation run を作る -----------------------------------------
full = io.readcsv(fullfile(s.verilator_dir, 'rnm_nominal_full.csv'));
dig = io.readcsv(fullfile(s.verilator_dir, 'system_nominal.csv'));
t10 = full.time_ns * 1e-9;    % s (10 ns grid)
t100 = dig.time_ns * 1e-9;    % s (100 ns grid)

% analog は 10 ns grid (RNM の integration grid)。logic は 100 ns tick のまま。
% 100 ns しかない debug 値を 10 ns へ補間して作り直さない。
vals = { ...
    mkts('vout', t10, full.vout), ...
    mkts('vctrl', t10, full.vctrl), ...
    mkts('pg_cmp', t10, double(full.pg_cmp)), ...
    mkts('en', t100, double(dig.en)), ...
    mkts('load_hi', t100, double(dig.load_hi)), ...
    mkts('pgood', t100, double(dig.pgood)), ...
    mkts('state', t100, double(dig.state)), ...
    mkts('rst', t100, double(dig.rst))};
names = cellfun(@(t) t.Name, vals, 'UniformOutput', false);

impl_id = Simulink.sdi.createRun(IMPLEMENTATION_RUN_NAME, 'namevalue', names, vals);
impl_run = Simulink.sdi.getRun(impl_id);
% timeseries の Name が Signal 名になる。念のため sourceNames で揃っているか確認する。
cur = signal_names(impl_run);
fix = false;
for k = 1:numel(names)
    if ~any(strcmp(cur, names{k}))
        i = find_signal(impl_run, names{k});
        if isempty(i)
            sigs = sigmap(impl_run);
            fn = fieldnames(sigs);
            sig = sigs.(fn{k});
            sig.Name = names{k};
            fix = true;
        end
    end
end
if fix
    cur = signal_names(impl_run);
end

% ---- 3. interpolation: analog linear / logic zoh ---------------------------
set_interp(ref_run, ZOH);
set_interp(impl_run, ZOH);

% ---- 4. 4x1 comparison view -------------------------------------------------
Simulink.sdi.clearAllSubPlots();
Simulink.sdi.setSubPlotLayout(4, 1);
plot_pair(ref_run, impl_run, MAIN);

% ---- 5. save ----------------------------------------------------------------
if isfile(s.comparison_session), delete(s.comparison_session); end
Simulink.sdi.save(s.comparison_session);
assert(isfile(s.comparison_session), 'talkrtl:Comparison', ...
    'SDI session を保存できませんでした: %s', s.comparison_session);

% ---- 6. reload して同じ内容が残っているかを確認する ------------------------
Simulink.sdi.clear();
ok2 = Simulink.sdi.load(s.comparison_session);
ids2 = Simulink.sdi.getAllRunIDs();
info = struct('path', s.comparison_session, 'saved', true, 'bytes', dir(s.comparison_session).bytes, ...
    'sha256', io.sha256(s.comparison_session), 'loaded_first', loaded, 'reload_ok', ok2, ...
    'reference_session', s.reference_session, 'run_count', numel(ids2), ...
    'reference_run_name', REFERENCE_RUN_NAME, 'implementation_run_name', IMPLEMENTATION_RUN_NAME, ...
    'subplot_layout', '4x1', 'run_names', {{}}, 'signals', struct(), ...
    'interpolation', struct(), 'main_signals', {MAIN}, 'extra_signals', {EXTRA}, ...
    'signal_sources', struct(), 'checks', struct('check', {}, 'ok', {}, 'detail', {}));

C = {};
C = push(C, 'sdi.run_count_2', numel(ids2) == 2, sprintf('run count after reload = %d', numel(ids2)));
rn = {};
for k = 1:numel(ids2)
    r = Simulink.sdi.getRun(ids2(k));
    rn{end + 1} = r.Name; %#ok<AGROW>
    info.signals.(safefield(r.Name)) = signal_names(r);
    info.interpolation.(safefield(r.Name)) = interp_map(r);
end
info.run_names = rn;
C = push(C, 'sdi.reference_run_present', any(strcmp(rn, REFERENCE_RUN_NAME)), ...
    sprintf('runs = [%s]', strjoin(rn, ' | ')));
C = push(C, 'sdi.implementation_run_present', any(strcmp(rn, IMPLEMENTATION_RUN_NAME)), ...
    sprintf('runs = [%s]', strjoin(rn, ' | ')));

for k = 1:numel(ids2)
    r = Simulink.sdi.getRun(ids2(k));
    nm = signal_names(r);
    miss = MAIN(~ismember(MAIN, nm));
    C = push(C, ['sdi.required_signals.' safefield(r.Name)], isempty(miss), ...
        sprintf('run "%s" signals {%s}; missing main = [%s]', r.Name, strjoin(nm, ','), strjoin(miss, ',')));
end

zoh_ok = true;
zoh_detail = {};
for k = 1:numel(ids2)
    r = Simulink.sdi.getRun(ids2(k));
    im = interp_map(r);
    fn = fieldnames(im);
    for m = 1:numel(fn)
        inzoh = any(strcmp(ZOH, fn{m}));
        want = 'linear';
        if inzoh, want = 'zoh'; end
        if ~strcmpi(im.(fn{m}), want)
            zoh_ok = false;
            zoh_detail{end + 1} = sprintf('%s/%s=%s(want %s)', r.Name, fn{m}, im.(fn{m}), want); %#ok<AGROW>
        end
    end
end
C = push(C, 'sdi.logic_uses_zoh', zoh_ok, ...
    sprintf('logic/discrete signals use zero-order hold%s', ...
    ternary(isempty(zoh_detail), '', ['; unexpected: ' strjoin(zoh_detail, '; ')])));

lay = 'unknown';
try
    lay = mat2str(Simulink.sdi.getSubPlotLayout());
catch ME
    C = push(C, 'sdi.layout_readable', false, ME.message);
end
C = push(C, 'sdi.layout_4x1', strcmp(lay, '[4;1]'), sprintf('subplot layout = %s', lay));

info.checks = [C{:}];
info.failed = {info.checks(~[info.checks.ok]).check};
info.verdict = tf(all([info.checks.ok]));
end

% ---------------------------------------------------------------------------

function t = mkts(name, time_s, data)
t = timeseries(double(data), double(time_s(:)));
t.Name = name;
end

function nm = signal_names(run)
ids = run.getAllSignalIDs();
nm = cell(1, numel(ids));
for k = 1:numel(ids)
    s = Simulink.sdi.getSignal(ids(k));
    nm{k} = s.Name;
end
end

function im = interp_map(run)
ids = run.getAllSignalIDs();
im = struct();
for k = 1:numel(ids)
    s = Simulink.sdi.getSignal(ids(k));
    im.(safefield(s.Name)) = s.InterpMethod;
end
end

function set_interp(run, zoh_list)
ids = run.getAllSignalIDs();
for k = 1:numel(ids)
    s = Simulink.sdi.getSignal(ids(k));
    if s.InterpMethod == "" || isempty(s.InterpMethod)
        continue
    end
    nm = s.Name;
    if any(strcmp(zoh_list, nm))
        s.InterpMethod = 'zoh';
    elseif ~any(strcmp({'rst'}, nm))
        s.InterpMethod = 'linear';
    end
end
end

function plot_pair(ref_run, impl_run, names)
rows = struct('vout', 1, 'pg_cmp', 2, 'pgood', 3, 'state', 4);
runs = {ref_run, impl_run};
for k = 1:numel(names)
    nm = names{k};
    if ~isfield(rows, nm), continue; end
    row = rows.(nm);
    for j = 1:numel(runs)
        s = find_signal(runs{j}, nm);
        if ~isempty(s)
            s.plotOnSubPlot(row, 1, true);
        end
    end
end
end

function s = find_signal(run, name)
s = [];
ids = run.getAllSignalIDs();
for k = 1:numel(ids)
    cand = Simulink.sdi.getSignal(ids(k));
    if strcmp(cand.Name, name)
        s = cand;
        return
    end
end
end

function m = safefield(name)
m = regexprep(char(name), '[^A-Za-z0-9_]', '_');
if isempty(m) || ~isletter(m(1))
    m = ['s_' m];
end
end

function C = push(C, name, ok, detail)
C{end + 1} = struct('check', name, 'ok', logical(ok), 'detail', detail);
fprintf('  [%s] %s: %s\n', tf(ok), name, detail);
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
