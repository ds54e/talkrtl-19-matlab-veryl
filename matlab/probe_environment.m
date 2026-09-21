function report = probe_environment()
% 公開デモに必要な製品 (MATLAB / Simulink / Simscape / Stateflow) と基本 Simulink 実行を確認する。
% LDO/Stateflow の実行検証ではない。
root = fileparts(fileparts(mfilename('fullpath')));
out = fullfile(root, 'results', 'generated', 'preflight');
if ~isfolder(out), mkdir(out); end
products = ver;
names = {products.Name};
has = @(name) any(strcmp(names, name));
report = struct('state', 'STARTED', ...
    'matlab_version', version, 'release', version('-release'), ...
    'architecture', computer('arch'), 'is_windows', ispc, ...
    'simulink_smoke', 'NOT_RUN', ...
    'has_simulink', has('Simulink'), ...
    'has_simscape', has('Simscape'), ...
    'has_stateflow', has('Stateflow'));
report.products = struct('name', {products.Name}, 'version', {products.Version});
reportPath = fullfile(out, 'environment.json');
try
    assert(ispc, 'talkrtl:WrongPlatform', 'Windows MATLAB を使用してください。');
    assert(has('MATLAB') && has('Simulink'), ...
        'talkrtl:MissingBaseProduct', 'MATLAB / Simulink が必要です。');
    assert(has('Simscape'), 'talkrtl:MissingProduct', 'Simscape が必要です。');
    assert(has('Stateflow'), 'talkrtl:MissingProduct', 'Stateflow が必要です。');
    load_system('simulink');
    [~, suffix] = fileparts(tempname);
    mdl = ['talkrtl_probe_' suffix];
    new_system(mdl);
    cleanupModel = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>
    set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
        'FixedStep', '1', 'StopTime', '1');
    add_block('simulink/Sources/Constant', [mdl '/Input'], 'Value', '1');
    add_block('simulink/Sinks/Out1', [mdl '/Output']);
    add_line(mdl, 'Input/1', 'Output/1');
    set_param(mdl, 'SimulationCommand', 'update');
    sim(mdl);
    report.simulink_smoke = 'PASS';
    report.state = 'PREFLIGHT_PASS';
    writeReport(reportPath, report);
    disp(jsonencode(report));
catch ME
    report.state = 'BLOCKED';
    report.error_identifier = ME.identifier;
    report.error_message = ME.message;
    writeReport(reportPath, report);
    rethrow(ME);
end
end

function writeReport(path, report)
[fid, message] = fopen(path, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'talkrtl:ReportWrite', '%s', message);
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(report));
end
