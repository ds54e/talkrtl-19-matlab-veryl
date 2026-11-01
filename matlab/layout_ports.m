function ports=layout_ports(mdl,sys)
% Stable terminal names. Physical subsystem ports use their PMIO block name.
ports=struct('id',{},'handle',{},'block',{},'group',{},'line',{});
blocks=find_system(sys,'LookUnderMasks','all','FollowLinks','off', ...
    'SearchDepth',1,'Type','block');
blocks(strcmp(blocks,sys))=[];
for bi=1:numel(blocks)
    block=blocks{bi};relative=block(numel(mdl)+2:end);
    ph=get_param(block,'PortHandles');
    pmio={};
    if strcmp(get_param(block,'BlockType'),'SubSystem') && isempty(get_param(block,'ReferenceBlock'))
        pmio=find_system(block,'LookUnderMasks','all','FollowLinks','off', ...
            'SearchDepth',1,'BlockType','PMIOPort');
    end
    for field=fieldnames(ph)'
        group=field{1};
        aliases={};
        if ~isempty(pmio) && ismember(group,{'LConn','RConn'})
            side='Left';if strcmp(group,'RConn'),side='Right';end
            selected=pmio(cellfun(@(b)strcmp(get_param(b,'Side'),side),pmio));
            numbers=cellfun(@(b)str2double(get_param(b,'Port')),selected);
            [~,order]=sort(numbers);selected=selected(order);
            aliases=cellfun(@(b)get_param(b,'Name'),selected,'UniformOutput',false);
            assert(numel(aliases)==numel(ph.(group)), ...
                'talkrtl:LayoutPorts','Physical interface mismatch: %s.',relative);
        end
        for pi=1:numel(ph.(group))
            h=ph.(group)(pi);
            suffix=sprintf('%s:%d',group,pi);
            if ~isempty(aliases),suffix=['connection:' aliases{pi}];end
            ports(end+1)=struct('id',[relative '::' suffix], ...
                'handle',h,'block',relative,'group',group,'line',get_param(h,'Line')); %#ok<AGROW>
        end
    end
end
if ~isempty(ports),[~,order]=sort({ports.id});ports=ports(order);end
end
