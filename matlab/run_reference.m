function reference_id = run_reference()
s = demo_paths();
fprintf('=== reference: Simscape LDO + Stateflow supervisor ===\n');
Simulink.sdi.clear();
load_system(s.model_file);

% Root inputs are en, load_hi, rst. SimulationInput leaves the saved model intact.
t = (0:10e-9:50e-6)';
en = double(t >= 2e-6);
load_hi = double(t >= 25e-6 & t < 35e-6);
input = Simulink.SimulationInput('ldo_demo');
input = input.setExternalInput([t, en, load_hi, zeros(size(t))]);
sim(input);
ids = Simulink.sdi.getAllRunIDs();
reference_id = ids(end);
end
