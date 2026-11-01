function policy = comparison_policy()
% Demo acceptance limits, shared by CSV checks and the SDI Compare pane.
% Analog limits are absolute engineering budgets; relative/time tolerances
% remain zero. Digital signals must match exactly.
policy.analog = {'vout', 'vfb', 'vctrl', 'ipass'};
policy.digital = {'pgood', 'state', 'en', 'load_hi', 'pg_cmp', 'rst'};
policy.names = [policy.analog policy.digital];
policy.absolute = struct('vout', 1e-3, 'vfb', 0.5e-3, ...
    'vctrl', 5e-3, 'ipass', 20e-6);
% vfb is half vout; ipass = gm_pass * vctrl with gm_pass = 4 mA.
policy.units = struct('vout', 'V', 'vfb', 'V', 'ipass', 'A');
policy.scalar_mV = 0.1;
policy.crossing_ns = 0;
end
