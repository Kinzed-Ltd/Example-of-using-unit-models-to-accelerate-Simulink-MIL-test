function setup

currPath = fileparts(mfilename('fullpath'));
subMdlPath = fullfile(currPath, 'sub_models');
addpath(currPath);
addpath(subMdlPath);

cachePath = fullfile(currPath, 'sim_files', 'cache');
codeGenPath = fullfile(currPath, 'sim_files', 'codeGen');

Simulink.fileGenControl('set', 'CacheFolder', cachePath, ...
   'CodeGenFolder', codeGenPath, 'createDir',true);
   
open_system('Hybrid_vehicle_MIL');

end