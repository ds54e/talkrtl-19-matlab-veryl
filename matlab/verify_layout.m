function verify_layout()
% Regression check for saved geometry, idempotence and safe mismatch rejection.
paths=demo_paths();
expected=jsondecode(fileread(paths.layout_file));
[~,name]=fileparts(tempname);name=matlab.lang.makeValidName(['layout_' name]);
file=[tempname '.slx'];profileFile=[tempname '.json'];wrong=[name '_wrong'];
cleaner=onCleanup(@()cleanup(name,wrong,file,profileFile));
build_model('ModelName',name,'Save',false,'FixedStep',20e-9,'StopTime',45e-6);
assert(str2double(get_param(name,'FixedStep'))==20e-9);
assert(str2double(get_param(name,'StopTime'))==45e-6);
set_param(name,'SimulationCommand','update');
save_system(name,file);close_system(name,0);
% MATLAB uses the file basename when reopening a differently named model.
[~,savedName]=fileparts(file);
load_system(file);
loadedCleaner=onCleanup(@()closeIfLoaded(savedName));
actual=jsondecode(jsonencode(layout_profile(savedName)));
assert(isequaln(expected,actual),'talkrtl:LayoutRoundtrip','Saved layout differs from the approved profile.');
apply_layout(savedName);
assert(isequaln(actual,jsondecode(jsonencode(layout_profile(savedName)))), ...
    'talkrtl:LayoutIdempotence','Repeated application changed the layout.');
capture_layout(savedName,profileFile);
assert(isequaln(expected,jsondecode(fileread(profileFile))), ...
    'talkrtl:LayoutCapture','Captured layout differs from the approved profile.');
build_model('ModelName',wrong,'Supervisor',false,'LayoutFile','','Save',false);
before=layout_profile(wrong);
try
    apply_layout(wrong);
    error('talkrtl:LayoutTest','Expected a topology mismatch.');
catch err
    assert(strcmp(err.identifier,'talkrtl:LayoutMismatch'),'%s',err.message);
end
assert(isequaln(before,layout_profile(wrong)),'Rejected layout changed the model.');
fprintf('Layout checks passed: saved profile, capture, repeat application, solver options, mismatch rejection.\n');
end
function cleanup(name,wrong,file,profileFile)
closeIfLoaded(name);closeIfLoaded(wrong);
[~,savedName]=fileparts(file);closeIfLoaded(savedName);
if isfile(file),delete(file);end
if isfile(profileFile),delete(profileFile);end
end
function closeIfLoaded(name)
if bdIsLoaded(name),close_system(name,0);end
end
