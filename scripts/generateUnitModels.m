function generateUnitModels

thisPath   = fileparts(mfilename('fullpath'));
unitPath   = fullfile(fileparts(thisPath), 'unit_models');
mdlName    = 'Hybrid_vehicle_MIL';
subNames   = {'Env', 'Drv', 'Vco', 'Edr', 'GbxRe', 'Brk', 'GbxFr', 'Bdy', 'Ice', 'Pnt'};

fromWsSrc  = 'simulink/Sources/From Workspace';
unitDlySrc = 'simulink/Discrete/Unit Delay';
ssSrc      = 'simulink/Commonly Used Blocks/Subsystem';
inPrtSrc   = 'simulink/Sources/In1';
dispSrc    = 'simulink/Sinks/Display';
matFcnSrc  = 'eml_lib/MATLAB Function';
notSrc     = 'simulink/Logic and Bit Operations/Logical Operator';
srSrc      = ['simulink_extras/Flip Flops/S-R' char(10) 'Flip-Flop'];
gndSrc     = 'simulink/Sources/Ground';
terSrc     = 'simulink/Sinks/Terminator';

unitNum     = numel(subNames);
unitNumChar = num2str(unitNum);

% --- Pre-compute port names from each referenced model and full MIL block paths ---
load_system(mdlName);
blkPaths = cell(1, unitNum);
inNames  = cell(1, unitNum);
outNames = cell(1, unitNum);
for i_unit = 1:unitNum
    % Find the model reference block in MIL by its ModelName property
    found = find_system(mdlName, 'SearchDepth', 1, 'BlockType', 'ModelReference', ...
        'ModelName', subNames{i_unit});
    blkPaths{i_unit} = found{1};

    % Load the referenced model to read Inport/Outport block names
    load_system(subNames{i_unit});
    inPrts  = find_system(subNames{i_unit}, 'SearchDepth', 1, 'BlockType', 'Inport');
    outPrts = find_system(subNames{i_unit}, 'SearchDepth', 1, 'BlockType', 'Outport');

    % Sort by port number so order matches the block's port handles
    portNums = cellfun(@(p) str2double(get_param(p, 'Port')), inPrts);
    [~, idx] = sort(portNums);
    inPrts = inPrts(idx);

    inNames{i_unit} = cell(1, numel(inPrts));
    for k = 1:numel(inPrts)
        inNames{i_unit}{k} = get_param(inPrts{k}, 'Name');
    end
    outNames{i_unit} = get_param(outPrts{1}, 'Name');
end
close_system(mdlName, 0);

% --- Generate unit models ---
for i_unit = 1:unitNum
    baseName    = subNames{i_unit};
    inNamesThis = inNames{i_unit};
    outBusName  = upper(outNames{i_unit});   % e.g. 'ENV_BUS'

    % Determine which inputs come from downstream subsystems (need Unit Delay)
    b_addDelay = false(1, numel(inNamesThis));
    inBusNames = cell(1, numel(inNamesThis));
    for i_ln = 1:numel(inNamesThis)
        inBusNames{i_ln} = upper(inNamesThis{i_ln});
        producer = regexprep(inNamesThis{i_ln}, '_[Bb]us$', '');
        prodIdx  = find(strcmp(subNames, producer), 1);
        if ~isempty(prodIdx) && prodIdx > i_unit
            b_addDelay(i_ln) = true;
        end
    end

    unitMdlName  = [baseName '_Unit'];
    unitFullName = fullfile(unitPath, [unitMdlName '.slx']);
    disp(['(' num2str(i_unit) '/' unitNumChar ') Generating unit model: ' unitFullName])

    if exist(unitMdlName, 'file') == 4
        bdclose(unitMdlName)
        delete(which(unitMdlName))
    end

    % Create unit model using MIL as a blank template
    load_system(mdlName);
    Simulink.BlockDiagram.deleteContents(mdlName);
    mdlWS = get_param(mdlName, 'ModelWorkspace');
    mdlWS.clear;
    save_system(mdlName, unitFullName);

    % Reload original MIL (save_system renamed the in-memory model to unitMdlName)
    load_system(mdlName);

    % Copy model-reference block from MIL into unit model
    mainSSName = [unitMdlName '/' baseName];
    add_block(blkPaths{i_unit}, mainSSName, 'MakeNameUnique', 'on');

    % Create From Workspace blocks for each input
    mainPrtHdls = get_param(mainSSName, 'PortHandles');
    inPrtLst    = mainPrtHdls.Inport;
    for i_prt = 1:numel(inPrtLst)
        busName = inBusNames{i_prt};
        pos     = get_param(inPrtLst(i_prt), 'Position');

        inBusBlkName = [unitMdlName '/From_' busName];
        add_block(fromWsSrc, inBusBlkName, 'MakeNameUnique', 'on');
        fromPos = [pos(1)-250, pos(2)-8, pos(1)-150, pos(2)+8];
        set_param(inBusBlkName, 'Position',       fromPos);
        set_param(inBusBlkName, 'VariableName',   ['WS_' busName]);
        set_param(inBusBlkName, 'OutDataTypeStr', ['Bus: ' busName]);
        setFromWorkspaceFormat(inBusBlkName);

        if b_addDelay(i_prt)
            udBlkName = ['ud_' busName];
            udName    = [unitMdlName '/' udBlkName];
            udPos     = [pos(1)-75-10, pos(2)-10, pos(1)-75+10, pos(2)+10];
            add_block(unitDlySrc, udName, 'MakeNameUnique', 'on');
            set_param(udName, 'Position', udPos);
            set_param(udName, 'ShowName', 'off');
            add_line(unitMdlName, ['From_' busName '/1'], [udBlkName '/1']);
            add_line(unitMdlName, [udBlkName '/1'],       [baseName '/' num2str(i_prt)]);
        else
            add_line(unitMdlName, ['From_' busName '/1'], [baseName '/' num2str(i_prt)]);
        end
    end

    %% Add Consistency Check

    % From Workspace for expected output bus recording
    mainOutPrtPos      = get_param(mainPrtHdls.Outport(1), 'Position');
    chkBusPos          = [mainOutPrtPos(1)+50, mainOutPrtPos(2)-26, ...
                          mainOutPrtPos(1)+150, mainOutPrtPos(2)-10];
    chkBusBlkNameShort = ['From_' outBusName];
    chkBusBlkName      = [unitMdlName '/' chkBusBlkNameShort];
    add_block(fromWsSrc, chkBusBlkName, 'MakeNameUnique', 'on');
    set_param(chkBusBlkName, 'Position',       chkBusPos);
    set_param(chkBusBlkName, 'VariableName',   ['WS_' outBusName]);
    set_param(chkBusBlkName, 'OutDataTypeStr', ['Bus: ' outBusName]);
    setFromWorkspaceFormat(chkBusBlkName);

    % Consistency-check subsystem shell
    ssPos       = [chkBusPos(3)+30, chkBusPos(2)-5, chkBusPos(3)+140, chkBusPos(2)+35];
    ssNameShort = 'consistency_check';
    ckSSName    = [unitMdlName '/' ssNameShort];
    add_block(ssSrc, ckSSName);
    set_param(ckSSName, 'Position', ssPos);
    ssHdl = get_param(ckSSName, 'Handle');
    lnHdl = find_system(ssHdl, 'FindAll', 'On', 'Type', 'Line');
    delete_line(lnHdl);
    ckInPrt  = find_system(ssHdl, 'BlockType', 'Inport');
    ckOutPrt = find_system(ssHdl, 'BlockType', 'Outport');
    set_param(ckInPrt,  'Name', 'bus1');
    set_param(ckOutPrt, 'Name', 'Pass');
    inPrtPos = get_param(ckInPrt, 'Position');
    bus2Pos  = [inPrtPos(1), inPrtPos(2)+45, inPrtPos(3), inPrtPos(4)+45];
    add_block(inPrtSrc, [ckSSName '/bus2']);
    set_param([ckSSName '/bus2'], 'Position', bus2Pos);

    % Outer connections to consistency_check
    add_line(unitMdlName, [chkBusBlkNameShort '/1'], [ssNameShort '/1']);
    add_line(unitMdlName, [baseName '/1'],            [ssNameShort '/2'], ...
        'autorouting', 'smart');

    % Display
    dispNameShort = 'Display';
    dispName      = [unitMdlName '/' dispNameShort];
    add_block(dispSrc, dispName);
    dispPos = [ssPos(3)+60, ssPos(2)+5, ssPos(3)+150, ssPos(4)-5];
    set_param(dispName, 'Position', dispPos);
    add_line(unitMdlName, [ssNameShort '/1'], [dispNameShort '/1']);

    % Inside consistency_check: MATLAB Function isequal(bus1, bus2)
    matFcnShortName = 'MATLAB Function';
    matFcnName      = [ckSSName '/' matFcnShortName];
    add_block(matFcnSrc, matFcnName);
    ssObj  = get_param(ckSSName, 'Object');
    sfObj  = ssObj.find('-isa', 'Stateflow.EMChart');
    sfObj.Script = ['function isEqual = fcn(bus1, bus2)' char(10) ...
        'isEqual = isequal(bus1, bus2);'];
    mfPos = [bus2Pos(3)+50, bus2Pos(2)-60, bus2Pos(3)+150, bus2Pos(2)+30];
    set_param(matFcnName, 'Position', mfPos);
    add_line(ckSSName, 'bus1/1', [matFcnShortName '/1']);
    add_line(ckSSName, 'bus2/1', [matFcnShortName '/2']);

    % NOT: isequal → S of SR latch (set when mismatch)
    notShortName = 'Logical Operator NOT';
    notName      = [ckSSName '/' notShortName];
    add_block(notSrc, notName);
    set_param(notName, 'Operator', 'NOT');
    notPos = [mfPos(3)+40, mfPos(2)+30, mfPos(3)+70, mfPos(4)-30];
    set_param(notName, 'Position', notPos);
    add_line(ckSSName, [matFcnShortName '/1'], [notShortName '/1']);

    % S-R Flip-Flop: sticky mismatch latch
    srShortName = 'S-R Flip-Flop';
    srName      = [ckSSName '/' srShortName];
    add_block(srSrc, srName);
    srPos = [notPos(3)+50, notPos(2)-3, notPos(3)+95, notPos(2)+72];
    set_param(srName, 'Position', srPos);
    add_line(ckSSName, [notShortName '/1'], [srShortName '/1']);

    % Ground → R (latch is never reset during simulation)
    gndShortName = 'Ground';
    gndName      = [ckSSName '/' gndShortName];
    add_block(gndSrc, gndName);
    srPrtHdls = get_param(srName, 'PortHandles');
    loPrtPos  = get_param(srPrtHdls.Inport(2), 'Position');
    gndPos    = [srPos(1)-40, loPrtPos(2)-10, srPos(1)-20, loPrtPos(2)+10];
    set_param(gndName, 'Position', gndPos);
    add_line(ckSSName, [gndShortName '/1'], [srShortName '/2']);

    % Terminator on /Q output
    terShortName = 'Terminator';
    terName      = [ckSSName '/' terShortName];
    add_block(terSrc, terName);
    terPos = [srPos(3)+30, loPrtPos(2)-10, srPos(3)+50, loPrtPos(2)+10];
    set_param(terName, 'Position', terPos);
    add_line(ckSSName, [srShortName '/2'], [terShortName '/1']);

    % NOT2: invert Q → Pass=1 means no mismatch detected
    notShortName2 = 'Logical Operator NOT1';
    notName2      = [ckSSName '/' notShortName2];
    add_block(notSrc, notName2);
    set_param(notName2, 'Operator', 'NOT');
    hiPrtPos = get_param(srPrtHdls.Inport(1), 'Position');
    not2Pos  = [srPos(3)+40, hiPrtPos(2)-15, srPos(3)+70, hiPrtPos(2)+15];
    set_param(notName2, 'Position', not2Pos);
    add_line(ckSSName, [srShortName '/1'], [notShortName2 '/1']);

    % Link Outport (Pass)
    hiPrtPos = get_param(srPrtHdls.Inport(1), 'Position');
    outPos   = [not2Pos(3)+50, hiPrtPos(2)-7, not2Pos(3)+80, hiPrtPos(2)+7];
    set_param(ckOutPrt, 'Position', outPos);
    add_line(ckSSName, [notShortName2 '/1'], [get_param(ckOutPrt, 'Name') '/1']);

    set_param(unitMdlName, 'ZoomFactor', 'FitSystem');
    save_system(unitMdlName);
    bdclose(unitMdlName);
end
disp('Done!')
end

function setFromWorkspaceFormat(blk)
set_param(blk, 'ShowName',              'off');
set_param(blk, 'SampleTime',            '-1');
set_param(blk, 'Interpolate',           'off');
set_param(blk, 'OutputAfterFinalValue', 'Holding final value');
end
