local torch = require 'torch'
local nn = require 'nn'

local neural

local function playNN()
    --local input = torch.randn(1, 221):cl()
    local input = {}
    for i = 1, 221 do
        table.insert(input, math.random())
    end

    input = torch.Tensor(input):cl()

    local pred = neural:forward(input)

    local max = pred[1]
    local pos_i = 1
    for i = 2, 11 do
        if pred[i] > max then
            max = pred[i]
            pos_i = i
        end
    end

    max = pred[12]
    local rot_i = 12
    for i = 13, 15 do
        if pred[i] > max then
            max = pred[i]
            rot_i = i
        end
    end
    rot_i = rot_i - 11

    return pos_i, rot_i
end

local function loadCL()
    local p = io.open("err", "w")

    local ok, cunn = pcall(require, 'clnn')
    local ok2, cutorch = pcall(require, 'cltorch')
    if not ok then p:write('package clnn not found!') end
    if not ok2 then p:write('package cltorch not found!') end
    if ok and ok2 then
        p:write('using OpenCL on GPU 0...')
        cltorch.setDevice(1) -- note +1 to make it 0 indexed! sigh lua
        --torch.manualSeed(opt.seed)
    else
        p:write('If cltorch and clnn are installed, your OpenCL driver may be improperly configured.')
        p:write('Check your OpenCL driver installation, check output of clinfo command, and try again.')
        os.exit()
    end

    p:close()
end

local function main()
    loadCL()

    neural = nn.Sequential()
    neural:add(nn.Linear(221, 300))
    neural:add(nn.Tanh())
    neural:add(nn.Linear(300, 15))

    neural:cl()
    --nn.ClassNLLCriterion():cl()

    playNN()
end

main()
