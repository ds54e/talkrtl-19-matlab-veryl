function info = open_demo(varargin)
% 保存した comparison SDI session を再表示/検証する入口。
% batch では GUI を開かず 'OpenSdi', false で検証だけ行える。
%
%   open_demo('OpenSdi', false)
%
% session が無ければ再生成 command を示して loaded=false を返す。
% session の中身は source から再生成できる (大きな mldatx は commit しない)。
p = inputParser;
p.addParameter('Session', '');
p.addParameter('OpenSdi', true);
p.parse(varargin{:});
io = comparison_io();
s = io.paths();

if isempty(p.Results.Session)
    sdiPath = s.comparison_session;
else
    sdiPath = p.Results.Session;
end

REFERENCE_RUN_NAME = 'Reference: Simscape + Stateflow';
IMPLEMENTATION_RUN_NAME = 'Implementation: Verilator RNM + Veryl';
MAIN = {'vout', 'pg_cmp', 'pgood', 'state'};

info = struct('session', sdiPath, 'loaded', false, 'sdi_visible', false, ...
    'run_count', 0, 'run_names', {{}}, 'signals', {{}}, 'missing_main', {{}}, 'layout', '');

if ~isfile(sdiPath)
    fprintf('comparison SDI session がありません: %s\n', sdiPath);
    fprintf('再生成: bash tools/matlab-batch "addpath(''matlab''); run_demo"\n');
    fprintf('(Verilator 側: ./sim/run_verilator.sh)\n');
    return
end

Simulink.sdi.clear();
info.loaded = Simulink.sdi.load(sdiPath);
ids = Simulink.sdi.getAllRunIDs();
info.run_count = numel(ids);

names = cell(1, numel(ids));
sigs = cell(1, numel(ids));
missing = {};
for k = 1:numel(ids)
    r = Simulink.sdi.getRun(ids(k));
    names{k} = r.Name;
    ids_s = r.getAllSignalIDs();
    sn = cell(1, numel(ids_s));
    for m = 1:numel(ids_s)
        sg = Simulink.sdi.getSignal(ids_s(m));
        sn{m} = sg.Name;
    end
    sigs{k} = sn;
    miss = MAIN(~ismember(MAIN, sn));
    if ~isempty(miss)
        missing{end + 1} = sprintf('%s:{%s}', r.Name, strjoin(miss, ',')); %#ok<AGROW>
    end
end
info.run_names = names;
info.signals = sigs;
info.missing_main = missing;

% 必要なら 4x1 の比較 view を再構成する (programmatic に再現可能)
try
    Simulink.sdi.clearAllSubPlots();
    Simulink.sdi.setSubPlotLayout(4, 1);
    rows = struct('vout', 1, 'pg_cmp', 2, 'pgood', 3, 'state', 4);
    for k = 1:numel(ids)
        r = Simulink.sdi.getRun(ids(k));
        for f = fieldnames(rows)'
            nm = f{1};
            ids_s = r.getAllSignalIDs();
            for m = 1:numel(ids_s)
                sg = Simulink.sdi.getSignal(ids_s(m));
                if strcmp(sg.Name, nm)
                    sg.plotOnSubPlot(rows.(nm), 1, true);
                end
            end
        end
    end
    info.layout = mat2str(Simulink.sdi.getSubPlotLayout());
catch ME
    info.layout_error = ME.message;
end

if p.Results.OpenSdi
    Simulink.sdi.view;
    info.sdi_visible = true;
end

ok = info.loaded && info.run_count == 2 && ...
    any(strcmp(names, REFERENCE_RUN_NAME)) && any(strcmp(names, IMPLEMENTATION_RUN_NAME)) && isempty(missing);
info.check_pass = ok;

fprintf('SDI session : %s\n', sdiPath);
fprintf('loaded=%d run_count=%d layout=%s\n', info.loaded, info.run_count, info.layout);
fprintf('run names   : %s\n', strjoin(names, ' | '));
fprintf('reference run present      = %d\n', any(strcmp(names, REFERENCE_RUN_NAME)));
fprintf('implementation run present = %d\n', any(strcmp(names, IMPLEMENTATION_RUN_NAME)));
fprintf('required signals present = %d\n', isempty(missing));
if ~isempty(missing)
    fprintf('missing: %s\n', strjoin(missing, '; '));
end
fprintf('analog は 10 ns solver/RNM grid、digital は 100 ns tick。logic は zero-order hold。\n');
fprintf('再実行: bash tools/matlab-batch "addpath(''matlab''); run_comparison"\n');
fprintf('OPEN_DEMO: %s\n', tf(ok));
end

function s = tf(b)
if b, s = 'PASS'; else, s = 'FAIL'; end
end
