function result = run_demo()
reference_id = run_reference();
result.sdi = comparison_sdi(reference_id);
result.figure = comparison_figure();
result.pass = strcmp(result.sdi.verdict, 'PASS');
fprintf('run_demo: %s\n', result.sdi.verdict);
assert(result.pass, 'talkrtl:DemoFailed', 'SDI comparison failed.');
end
