function info = open_comparison(varargin)
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

if ~isfile(sdiPath)
    fprintf('comparison SDI session がありません: %s\n', sdiPath);
    fprintf('再生成: bash tools/matlab-batch.sh "addpath(''matlab''); run_demo"\n');
    info = struct('session', sdiPath, 'loaded', false);
    return
end

Simulink.sdi.clear();
loaded = Simulink.sdi.load(sdiPath);
ids = Simulink.sdi.getAllRunIDs();

Simulink.sdi.clearAllSubPlots();
Simulink.sdi.setSubPlotLayout(4, 1);
rows = struct('vout', 1, 'pg_cmp', 2, 'pgood', 3, 'state', 4);
for k = 1:numel(ids)
    r = Simulink.sdi.getRun(ids(k));
    sigs = r.getAllSignalIDs();
    for m = 1:numel(sigs)
        sg = Simulink.sdi.getSignal(sigs(m));
        if isfield(rows, sg.Name)
            sg.plotOnSubPlot(rows.(sg.Name), 1, true);
        end
    end
end

if p.Results.OpenSdi
    Simulink.sdi.view;
end

info = struct('session', sdiPath, 'loaded', logical(loaded), ...
    'run_count', numel(ids), 'sdi_visible', logical(p.Results.OpenSdi));
fprintf('SDI session: %s\n', sdiPath);
end
