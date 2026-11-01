function keys=layout_contract(profile)
% Geometry-independent identity of visible blocks, terminals, nets and chart edges.
keys={};
for b=profile.blocks(:)'
    keys{end+1}=['block|' b.path '|' b.type '|' strjoin(rowcell(b.ports),'|')]; %#ok<AGROW>
end
for s=profile.systems(:)'
    keys{end+1}=['diagram|' s.path]; %#ok<AGROW>
    for n=s.nets(:)'
        key=['net|' s.path '|' n.kind '|' strjoin(sort(rowcell(n.terminals)),'|')];
        if strcmp(n.kind,'signal'),key=[key '|source=' n.root];end
        keys{end+1}=key; %#ok<AGROW>
    end
end
for c=profile.charts(:)'
    keys{end+1}=['chart|' c.path]; %#ok<AGROW>
    for s=c.states(:)',keys{end+1}=['state|' c.path '|' s.name];end %#ok<AGROW>
    for t=c.transitions(:)'
        keys{end+1}=sprintf('edge|%s|%s|%s|%d',c.path,t.source,t.destination,t.order); %#ok<AGROW>
    end
end
keys=sort(keys);
end
function v=rowcell(v)
if isempty(v),v={};elseif ischar(v),v={v};elseif isstring(v),v=cellstr(v);end
v=reshape(v,1,[]);
end
