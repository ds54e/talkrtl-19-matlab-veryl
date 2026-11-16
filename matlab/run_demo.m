function result = run_demo()
% MATLAB side of the demo: simulate the reference model, compare it with the
% Xezim run in Simulation Data Inspector, and write the overview figure.
root = fileparts(fileparts(mfilename('fullpath')));
out = fullfile(root, 'results', 'generated');

ref = run_reference(fullfile(root, 'model', 'ldo_demo.slx'));
impl = load_xezim_run(fullfile(out, 'xezim', 'signals.csv'));
verdict = compare_runs(ref, impl, fullfile(out, 'sdi', 'comparison.mldatx'));
plot_rows(ref, impl, fullfile(out, 'comparison', 'overview.png'));

result = struct('pass', strcmp(verdict, 'PASS'), 'verdict', verdict);
assert(result.pass, 'talkrtl:DemoFailed', 'SDI comparison failed.');
end

function run = run_reference(model_file)
% Simscape LDO + Stateflow supervisor. Root inputs are en, load_hi and rst;
% SimulationInput leaves the saved model untouched.
fprintf('=== reference: Simscape LDO + Stateflow supervisor ===\n');
Simulink.sdi.clear();
load_system(model_file);
t = (0:10e-9:50e-6)';
en = double(t >= 2e-6);
load_hi = double(t >= 25e-6 & t < 35e-6);
input = Simulink.SimulationInput('ldo_demo');
input = input.setExternalInput([t, en, load_hi, zeros(size(t))]);
sim(input);
ids = Simulink.sdi.getAllRunIDs();
run = Simulink.sdi.getRun(ids(end));
run.Name = 'Reference: Simscape + Stateflow';
end

function run = load_xezim_run(csv)
% Every column after time_ns becomes one signal.
x = readtable(csv);
names = x.Properties.VariableNames(2:end);
vals = cellfun(@(n) timeseries(double(x.(n)), x.time_ns * 1e-9, 'Name', n), ...
    names, 'UniformOutput', false);
id = Simulink.sdi.createRun('Implementation: Xezim SV-RNM + Veryl + RgGen', ...
    'namevalue', names, vals);
run = Simulink.sdi.getRun(id);
end

function verdict = compare_runs(ref, impl, session)
% Analog signals within absolute limits, digital signals exact.
LIMITS = struct('vout', 1e-3, 'vfb', 0.5e-3, 'vctrl', 5e-3, 'ipass', 20e-6);
for run = [ref impl]
    for id = run.getAllSignalIDs()'
        sig = Simulink.sdi.getSignal(id);
        sig.OverrideGlobalTol = true;
        sig.RelTol = 0;
        sig.TimeTol = 0;
        if isfield(LIMITS, sig.Name)
            sig.AbsTol = LIMITS.(sig.Name);
            sig.InterpMethod = 'linear';
        else
            sig.AbsTol = 0;
            sig.InterpMethod = 'zoh';
        end
    end
end
diff = Simulink.sdi.compareRuns(ref.ID, impl.ID, 'AbsTol', 0, 'RelTol', 0, 'TimeTol', 0);
ok = 0;
for k = 1:diff.Count
    ok = ok + strcmp(char(diff.getResultByIndex(k).Status), 'WithinTolerance');
end
verdict = 'FAIL';
if diff.Count == 10 && ok == diff.Count, verdict = 'PASS'; end
fprintf('SDI Compare: %d/%d signals within tolerance (digital exact) : %s\n', ok, diff.Count, verdict);

% Keep the computed comparison and both runs for later viewing.
if ~isfolder(fileparts(session)), mkdir(fileparts(session)); end
if isfile(session), delete(session); end
saveResult(diff, session);
end

function plot_rows(ref, impl, figure_file)
% The same rows in the SDI window and in the README figure. The figure is one
% SDI snapshot per row, stacked, so the digital rows can stay thin; only the
% bottom row gets time labels and the user's SDI setting is restored.
ROWS = {'vout', 420; 'pg_cmp', 110; 'pgood', 110; 'en', 110; 'load_hi', 124};
n = size(ROWS, 1);
Simulink.sdi.clearAllSubPlots();
Simulink.sdi.setSubPlotLayout(n, 1);
for k = 1:n
    Simulink.sdi.setVisualization(k, 1, 'timeplot');   % SDI remembers this per row
    for sig = [ref.getSignalsByName(ROWS{k, 1}), impl.getSignalsByName(ROWS{k, 1})]
        sig.plotOnSubPlot(k, 1, true);
    end
end
% Snapshots in a separate pass: interleaving them with the window plots above
% left some figure rows empty.
labels = Simulink.sdi.getTickLabelsDisplay();
restore = onCleanup(@() Simulink.sdi.setTickLabelsDisplay(labels));
Simulink.sdi.setTickLabelsDisplay('y-axis');
img = [];
for k = 1:n
    snap = Simulink.sdi.CustomSnapshot;
    snap.Width = 1100;
    snap.Height = ROWS{k, 2};
    for sig = [ref.getSignalsByName(ROWS{k, 1}), impl.getSignalsByName(ROWS{k, 1})]
        snap.plotOnSubPlot(1, 1, sig, true);
    end
    if k == n, Simulink.sdi.setTickLabelsDisplay(labels); end
    f = [tempname '.png'];
    Simulink.sdi.snapshot('from', 'custom', 'to', 'file', 'filename', f, 'settings', snap);
    img = [img; imread(f)]; %#ok<AGROW>
    delete(f);
end
if ~isfolder(fileparts(figure_file)), mkdir(fileparts(figure_file)); end
imwrite(img, figure_file);
end
