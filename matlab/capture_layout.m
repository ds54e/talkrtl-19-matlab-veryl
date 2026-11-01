function profile=capture_layout(mdl,file)
% Save the current GUI layout. Save/reload the model first for stable geometry.
% Example: capture_layout('ldo_demo', 'model/layout/approved.json')
paths=demo_paths();
defaultFile=paths.layout_file;
if nargin<1 || isempty(mdl),mdl=paths.reference_model;end
if nargin<2,file=defaultFile;end
assert(bdIsLoaded(mdl),'talkrtl:LayoutModel','Open the model to capture first.');
mdl=get_param(bdroot(mdl),'Name');
assert(strcmp(get_param(mdl,'BlockDiagramType'),'model'), ...
    'talkrtl:LayoutModel','Cannot capture a library. Use save_demo_layout on the generated demo model.');
profile=layout_profile(mdl);
if strcmp(strrep(char(file),'\','/'),strrep(defaultFile,'\','/'))
    validateDemo(profile);
end
folder=fileparts(file);if ~isempty(folder) && ~isfolder(folder),mkdir(folder);end
fid=fopen(file,'w','n','UTF-8');
assert(fid~=-1,'talkrtl:LayoutFile','Cannot write layout file: %s',file);
closer=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(profile,'PrettyPrint',true));
fprintf('Captured %d blocks, %d diagrams and %d charts: %s\n', ...
    numel(profile.blocks),numel(profile.systems),numel(profile.charts),file);
end

function validateDemo(profile)
% Compare against the generator, never against a possibly overwritten JSON.
[~,token]=fileparts(tempname);
probe=matlab.lang.makeValidName(['layout_capture_' token]);
cleaner=onCleanup(@()closeProbe(probe));
build_model('ModelName',probe,'Save',false,'LayoutFile','');
expected=layout_contract(layout_profile(probe));
assert(isequal(expected,layout_contract(profile)), ...
    'talkrtl:LayoutModel', ...
    ['This is not the generated LDO model structure. The approved JSON was not changed. ' ...
     'Use save_demo_layout on the generated demo model. ' ...
     'For intentional structural changes, capture to a separate JSON file.']);
end
function closeProbe(mdl)
if bdIsLoaded(mdl),close_system(mdl,0);end
end
