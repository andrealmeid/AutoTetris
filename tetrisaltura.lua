#!/usr/local/bin/lua
-- termtris.lua
--
-- A tetris-inspired game made using the curses library.
--

package.path = package.path .. ";./?.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;/usr/local/lib/lua/5.1/?.lua;/usr/local/lib/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua"

package.cpath = package.cpath .. ";./?.so;/usr/local/lib/lua/5.1/?.so;/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so"

local curses = require 'curses'
local posix  = require 'posix'

local nn = require 'nn'
local torch = require 'torch'

-- Neural networks settings
local globalId = 0
local inputSize = 27
local hiddenUnits = 50
local hiddenUnits2 = 15

local units = {hiddenUnits, 0, hiddenUnits2, 0, 15}

------------------------------------------------------------------
-- Piece shapes.
------------------------------------------------------------------

-- The final form of the shapes array is set up in init so
-- that at runtime, s = shapes[shape_num][rot_num] is a 2D array
-- with s[x][y] = either 0 or 1, indicating the piece's shape.

local shapes

------------------------------------------------------------------
-- Declare internal globals.
------------------------------------------------------------------

local game_state -- Could also be 'paused' or 'over'.

local stdscr -- This will be the standard screen from the curses library.

local board_size
local board = {}  -- board[x][y] = <piece at (x, y)>; 0 = empty, -1 = border.
local val -- Shorthand to avoid magic numbers.

-- We'll write *shape* for an index into the shapes table; the
-- term *piece* also includes a rotation number and x, y coords.
local moving_piece = {}  -- Keys will be: shape, rot_num, x, y.

local function resetGlobals()
    game_state = 'playing'  -- Could also be 'paused' or 'over'.

    stdscr = nil  -- This will be the standard screen from the curses library.

    board_size = {x = 10, y = 20}
    board = {}  -- board[x][y] = <piece at (x, y)>; 0 = empty, -1 = border.
    val = {border = -1, empty = 0}  -- Shorthand to avoid magic numbers.

    -- We'll write *shape* for an index into the shapes table; the
    -- term *piece* also includes a rotation number and x, y coords.
    moving_piece = {}  -- Keys will be: shape, rot_num, x, y.

    shapes = {
    { {0,0,1,0},
      {0,1,1,1}
    },
    { {0,0,1,1},
      {0,1,1,0}
    },
    { {0,1,1,0},
      {0,0,1,1}
    },
    { {1,1,1,1},
      {0,0,0,0}
    },
    { {0,0,1,1},
      {0,0,1,1}
    },
    { {0,1,0,0},
      {0,1,1,1}
    },
    { {0,0,0,1},
      {0,1,1,1}
    }
}


end

------------------------------------------------------------------
-- Internal functions.
------------------------------------------------------------------

-- Accepts integer values corresponding to the 'colors' table
-- created by init. For example, call 'set_color(colors.black)'.
local function set_color(c)
    stdscr:attron(curses.color_pair(c))
end

-- This function calls callback(x, y) for each x, y coord
-- in the given piece. Example use using draw_point(x, y):
-- call_fn_for_xy_in_piece(moving_piece, draw_point)
local function call_fn_for_xy_in_piece(piece, callback, param)
    local s = shapes[piece.shape][piece.rot_num]
    for x, row in ipairs(s) do
        for y, val in ipairs(row) do
            if val == 1 then callback(piece.x + x, piece.y + y, param) end
        end
    end
end

local function draw_point(x, y, x_offset, color, point_char)
    point_char = point_char or ' '  -- Space is the default point_char.
    if color then set_color(color) end
    -- Don't draw pieces when the game is paused.
    if point_char == ' ' and game_state == 'paused' then return end
    stdscr:mvaddstr(y, x_offset + 2 * x + 0, point_char)
    stdscr:mvaddstr(y, x_offset + 2 * x + 1, point_char)
end

-- Returns true if and only if the move was valid.
local function set_moving_piece_if_valid(piece)
    -- Use values of moving_piece as defaults.
    for k, v in pairs(moving_piece) do
        if piece[k] == nil then piece[k] = moving_piece[k] end
    end
    local is_valid = true
    call_fn_for_xy_in_piece(piece, function (x, y)
        if board[x] and board[x][y] ~= val.empty then is_valid = false end
    end)
    if is_valid then moving_piece = piece end
    return is_valid
end

local function init(seed)
    -- Use the current time's microseconds as our random seed.
    math.randomseed(seed)

    -- Set up the shapes table.
    for s_index, s in ipairs(shapes) do
        shapes[s_index] = {}
        for rot_num = 1, 4 do
            -- Set up new_shape as s rotated by 90 degrees.
            local new_shape = {}
            local x_end = #s[1] + 1  -- Chosen so that x_end - x is in [1, x_max].
            for x = 1, #s[1] do      -- Coords x & y are indexes for the new shape.
                new_shape[x] = {}
                for y = 1, #s do
                    new_shape[x][y] = s[y][x_end - x]
                end
            end
            s = new_shape
            shapes[s_index][rot_num] = s
        end
    end

    -- Start up curses.
    curses.initscr()    -- Initialize the curses library and the terminal screen.
    curses.cbreak()     -- Turn off input line buffering.
    curses.echo(false)  -- Don't print out characters as the user types them.
    curses.nl(false)    -- Turn off special-case return/newline handling.
    curses.curs_set(0)  -- Hide the cursor.

    -- Set up colors.
    curses.start_color()
    if not curses.has_colors() then
        curses.endwin()
        print('Bummer! Looks like your terminal doesn\'t support colors :\'(')
        os.exit(1)
    end
    local colors = { white = 1, blue = 2, cyan = 3, green = 4,
    magenta = 5, red = 6, yellow = 7, black = 8 }
    for k, v in pairs(colors) do
        curses_color = curses['COLOR_' .. k:upper()]
        curses.init_pair(v, curses_color, curses_color)
    end
    colors.text, colors.over = 9, 10
    curses.init_pair(colors.text, curses.COLOR_WHITE, curses.COLOR_BLACK)
    curses.init_pair(colors.over, curses.COLOR_RED,   curses.COLOR_BLACK)

    -- Set up our standard screen.
    stdscr = curses.stdscr()
    stdscr:nodelay(true)  -- Make getch nonblocking.
    stdscr:keypad()       -- Correctly catch arrow key presses.

    -- Set up the board.
    local border = {x = board_size.x + 1, y = board_size.y + 1}
    for x = 0, border.x do
        board[x] = {}
        for y = 1, border.y do
            board[x][y] = val.empty
            if x == 0 or x == border.x or y == border.y then
                board[x][y] = val.border  -- This is a border cell.
            end
        end
    end

    -- Set up the next and currently moving piece.
    moving_piece = {shape = math.random(#shapes), rot_num = 1, x = 4, y = 0}
    -- Use a table so functions can edit its value without having to return it.
    next_piece = {shape = math.random(#shapes)}

    local stats = {level = 1, lines = 0, score = 0}  -- Player stats.

    -- fall.interval is the number of seconds between downward piece movements.
    local fall = {interval = 0.7}  -- A 'last_at' time is added to this table later.

    return stats, fall, colors, next_piece
end

local function draw_screen(stats, colors, next_piece)
    stdscr:erase()

    -- Update the screen dimensions.
    local scr_width = curses.cols()
    local win_width = 2 * (board_size.x + 2) + 16
    local x_margin = math.floor((scr_width - win_width) / 2)
    local x_labels = x_margin + win_width - 10

    -- Draw the board's border and non-falling pieces if we're not paused.
    local color_of_val = {[val.border] = colors.text, [val.empty] = colors.black}
    local char_of_val = {[val.border] = '|'}  -- This is the border character.
    if game_state == 'over' then color_of_val[val.border] = colors.over end
    for x = 0, board_size.x + 1 do
        for y = 1, board_size.y + 1 do
            local board_val = board[x][y]
            -- Draw ' ' for shape & empty points; '|' for border points.
            local pt_char = char_of_val[board_val] or ' '
            draw_point(x, y, x_margin, color_of_val[board_val] or board_val, pt_char)
        end
    end

    -- Write 'paused' if the we're paused; draw the moving piece otherwise.
    if game_state == 'paused' then
        set_color(colors.text)
        local x = x_margin + board_size.x - 1  -- Slightly left of center.
        stdscr:mvaddstr(math.floor(board_size.y / 2), x, 'paused')
    else
        set_color(moving_piece.shape)
        call_fn_for_xy_in_piece(moving_piece, draw_point, x_margin)
    end

    -- Draw the stats: level, lines, and score.
    set_color(colors.text)
    stdscr:mvaddstr( 9, x_labels, 'Level ' .. stats.level)
    stdscr:mvaddstr(11, x_labels, 'Lines ' .. stats.lines)
    stdscr:mvaddstr(13, x_labels, 'Score ' .. stats.score)
    if game_state == 'over' then
        stdscr:mvaddstr(16, x_labels, 'Game Over')
    end

    -- Draw the next piece.
    stdscr:mvaddstr(2, x_labels, '----------')
    stdscr:mvaddstr(7, x_labels, '---Next---')
    local piece = {shape = next_piece.shape, rot_num = 1, x = board_size.x + 5, y = 3}
    set_color(piece.shape)
    call_fn_for_xy_in_piece(piece, draw_point, x_margin)

    stdscr:refresh()
end

local function playNN(neural)
    --[[
    local input = {0,0,0,0,0,0,0}

    input[moving_piece.shape] = 1
]]--
    local input = {}

    for i = 1, 2 do
        for j = 1, 4 do
            table.insert(input, shapes[moving_piece.shape][1][j][i])
        end
    end

    for i = 1, 10 do
        for j = 1, 20 do
            if board[i][j] ~= 0 and board[i][j] ~= -1 then
                table.insert(input, 21 - j)
                break
            end
            if j == 20 then
                table.insert(input, 0)
            end
        end
    end

    for i = 1, 9 do
        table.insert(input, input[i+8] - input[i+9])
    end

    input = torch.Tensor(input):cl()

    local pred = neural:forward(input)

    local max = pred[1]
    local pos_i = 1
    for i = 2, 10 do
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
    rot_i = rot_i - 10

    return pos_i, rot_i
end

local lock_and_update_moving_piece

local function handle_input(stats, fall, next_piece, key, neural)
    --local key = stdscr:getch()  -- Nonblocking; returns nil if no key was pressed.
    if key == nil then return end

    if key == tostring('q'):byte(1) then  -- The q key quits.
        curses.endwin()
        os.exit(0)
    end

    if key == tostring('p'):byte(1) then  -- The p key pauses or unpauses.
        local switch = {playing = 'paused', paused = 'playing'}
        if switch[game_state] then game_state = switch[game_state] end
    end

    if game_state ~= 'playing' then return end  -- Arrow keys only work if playing.

    -- Handle the left, right, or up arrows.
    local new_rot_num = (moving_piece.rot_num % 4) + 1  -- Map 1->2->3->4->1.
    local moves = {[49]  = {x = moving_piece.x - 1},
    [50] = {x = moving_piece.x + 1},
    [51] = {rot_num = new_rot_num}}
    if moves[key] then set_moving_piece_if_valid(moves[key]) end

    -- Handle the down arrow.
    if key == 52 then
        while set_moving_piece_if_valid({y = moving_piece.y + 1}) do end
        lock_and_update_moving_piece(stats, fall, next_piece, neural)
    end
end

-- A funcao recebe uma posicao entre [1, 10] e uma rotacao [1, 4] e coloca a peca la
local function placePiece(position, rotation, stats, fall, next_piece, neural)
    local times = position - 5

    --print(position, rotation)

    if times <= 0 then
        for i = times, 0 do
            handle_input(stats, fall, next_piece, 49, neural)
        end
    else
        for i = 1, times do
            handle_input(stats, fall, next_piece, 50, neural)
        end
    end

    for i = rotation, 1, -1 do
        handle_input(stats, fall, next_piece, 51, neural)
    end

    handle_input(stats, fall, next_piece, 52, neural)
end

lock_and_update_moving_piece = function(stats, fall, next_piece, neural)
    call_fn_for_xy_in_piece(moving_piece, function (x, y)
        board[x][y] = moving_piece.shape  -- Lock the moving piece in place.
    end)

    stats.score = stats.score + moving_piece.y

    -- Clear any lines possibly filled up by the just-placed piece.
    local num_removed = 0
    local max_line_y = math.min(moving_piece.y + 4, board_size.y)
    for line_y = moving_piece.y + 1, max_line_y do
        local is_full_line = true
        for x = 1, board_size.x do
            if board[x][line_y] == val.empty then is_full_line = false end
        end
        if is_full_line then
            -- Remove the line at line_y.
            for y = line_y, 2, -1 do
                for x = 1, board_size.x do
                    board[x][y] = board[x][y - 1]
                end
            end
            -- Record the line and level updates.
            stats.lines = stats.lines + 1
            if stats.lines % 10 == 0 then  -- Level up when lines is a multiple of 10.
                stats.level = stats.level + 1
                fall.interval = fall.interval * 0.8  -- The pieces will fall faster.
            end
            num_removed = num_removed + 1
        end
    end
    if num_removed > 0 then curses.flash() end
    stats.score = stats.score + 2 * num_removed * num_removed

    
    -- Bring in the waiting next piece and set up a new next piece.
    moving_piece = {shape = next_piece.shape, rot_num = 1, x = 4, y = 0}
    if not set_moving_piece_if_valid(moving_piece) then
        game_state = 'over'
    end
    next_piece.shape = math.random(#shapes)
    
    local pos, rot = playNN(neural)
    placePiece(pos, rot, stats, fall, next_piece, neural)

end


local function lower_piece_at_right_time(stats, fall, next_piece, neural)
    -- This function does nothing if the game is paused or over.
    if game_state ~= 'playing' then return end

    local timeval = posix.gettimeofday()
    local timestamp = timeval.sec + timeval.usec * 1e-6
    if fall.last_at == nil then fall.last_at = timestamp end  -- Happens at startup.

    -- Do nothing until it's been fall.interval seconds since the last fall.
    if timestamp - fall.last_at < fall.interval then return end

    if not set_moving_piece_if_valid({y = moving_piece.y + 1}) then
        lock_and_update_moving_piece(stats, fall, next_piece, neural)
    end
    fall.last_at = timestamp
end

local function loadCL()
    local p = io.open("err", "w")

    local ok, clnn = pcall(require, 'clnn')
    local ok2, cltorch = pcall(require, 'cltorch')
    if not ok then p:write('package clnn not found!') end
    if not ok2 then p:write('package cltorch not found!') end
    if ok and ok2 then
        p:write('using OpenCL on GPU 0...')
        cltorch.setDevice(1) -- note +1 to make it 0 indexed! sigh lua
        --torch.manualSeed(opt.seed)
    else
        p:write('If cltorch and clnn are installed, your OpenCL driver may be improperly configured.')
        p:write('Check your OpenCL driver installation, check output of clinfo command, and try again.')
        p:close()
        os.exit()
    end

    p:close()
end



------------------------------------------------------------------
-- Main.
------------------------------------------------------------------

local function main(neural, seed)
    resetGlobals()

    local stats, fall, colors, next_piece = init(seed)
    
    --nn.ClassNLLCriterion():cl()

    local pos, rot = playNN(neural, next_piece)
    placePiece(pos, rot, stats, fall, next_piece, neural)
    while game_state ~= 'over' do  -- Main loop.
        local key = stdscr:getch()
        handle_input(stats, fall, next_piece, key, neural)
        lower_piece_at_right_time(stats, fall, next_piece, neural)
        draw_screen(stats, colors, next_piece)
        --handle_input(stats, fall, next_piece, 51)
        -- Don't poll for input much faster than the display can change.
        --local sec, nsec = 0, 5e6  -- 0.005 seconds.
        --posix.nanosleep(sec, nsec)
    end

    return stats
end

local function bubbleSort(stats)
    for i = 1, #stats do
        for j = #stats, i, -1 do
            if stats[i][1].lines < stats[j][1].lines or (stats[i][1].lines == stats[j][1].lines and stats[i][1].score < stats[j][1].score) then
                local aux = stats[i]
                stats[i] = stats[j]
                stats[j] = aux
            end
        end
    end
end

loadCL()

local function generateNN(num)
    local neurals = {}

    for i = 1, num do
        local neu = nn.Sequential()

        local firstLayer = nn.Linear(inputSize, hiddenUnits)
        local secondLayer = nn.Linear(hiddenUnits, hiddenUnits2)
        local thirdLayer = nn.Linear(hiddenUnits2, 15)

        neu:add(firstLayer)
        neu:add(nn.Sigmoid())
        neu:add(secondLayer)
        neu:add(nn.Sigmoid())
        neu:add(thirdLayer)

        neu:cl()

        local network = {nn = neu, score = nil, id = globalId}
        globalId = globalId +1

        table.insert(neurals, network)
    end

    return neurals
end

local function TableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

local function mutate(network, chance)
    for i = 1, hiddenUnits do
        local rand = math.random(100)

        if rand <= chance then
            local rand2 = math.random(100)

            if rand2 <= 20 then
                for j = 1, inputSize do
                    network.modules[1].weight[i][j] = math.random()*30 -15
                end
            else
                local offset = math.random() -0.5

                for j = 1, inputSize do
                    network.modules[1].weight[i][j] = network.modules[1].weight[i][j] + offset
                end
            end
        end
    end

    for i = 1, hiddenUnits2 do
        local rand = math.random(100)

        if rand <= chance then
            local rand2 = math.random(100)

            if rand2 <= 20 then
                for j = 1, hiddenUnits do
                    network.modules[3].weight[i][j] = math.random()*30 -15
                end
            else
                local offset = math.random() -0.5

                for j = 1, hiddenUnits do
                    network.modules[3].weight[i][j] = network.modules[3].weight[i][j] + offset
                end
            end
        end
    end

    for i = 1, 15 do
        local rand = math.random(100)

        if rand <= chance then
            local rand2 = math.random(100)

            if rand2 <= 20 then
                for j = 1, hiddenUnits2 do
                    network.modules[5].weight[i][j] = math.random()*30 -15
                end
            else
                local offset = math.random() -0.5

                for j = 1, hiddenUnits2 do
                    network.modules[5].weight[i][j] = network.modules[5].weight[i][j] + offset
                end
            end
        end
    end

    return network
end

local function removeDuplicates(table)
    local hash = {}
    local res = {}

    for _,v in ipairs(table) do
        if (not hash[v]) then
            res[#res+1] = v
            hash[v] = true
        end
    end

    return res
end

local function crossover(network1, network2) -- should make a copy
    local neu = nn.Sequential()

    neu:add(nn.Linear(inputSize, hiddenUnits))
    neu:add(nn.Sigmoid())
    neu:add(nn.Linear(hiddenUnits, hiddenUnits2))
    neu:add(nn.Sigmoid())
    neu:add(nn.Linear(hiddenUnits, 15))

    neu:cl()

    for j = 1, 5, 2 do
        neu.modules[j] = network2.nn.modules[j]:clone()

        local neurons = {}
        for i = 1, math.ceil(units[j] * 0.25) do
            table.insert(neurons, math.random(units[j]))
        end
        neurons = removeDuplicates(neurons)

        for i = 1, #neurons do
            local sink = neu.modules[j].weight:select(1, neurons[i])
            local source = network1.nn.modules[j].weight:select(1, neurons[i])

            sink:copy(source)
        end
    end

    neu = mutate(neu, 30)

    local newNetwork = {nn = neu, score = nil, id = globalId}
    globalId = globalId +1

    return newNetwork
end

local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then
       io.close(f)
       return true
   else
       return false
   end
end

local nnNum = 30

local file = io.open("out", "w")

local networks = generateNN(nnNum)
local start = 1
if file_exists("checkpoint") then
    file:write("Loading checkpoint\n")
    file:flush()
    local check = torch.load("checkpoint")
    networks = check[2]
    start = check[1]
end

local finalStats = {}

for j = start, 3000 do
    local seed = os.time()
    local allStats = {}
    --local k = j > 1 and 11 or 1
    for i = 1, nnNum do
        local avgScore = 0.0
        local avgLines = 0.0
        for k = 1, 10 do
            local curScore = main(networks[i].nn, seed + k*1000)
            avgScore = avgScore + curScore.score
            avgLines = avgLines + curScore.lines
        end
        avgScore = avgScore / 10.0
        avgLines = avgLines / 10.0
        table.insert(allStats, {{score = avgScore, lines = avgLines}, networks[i]})
    end

    bubbleSort(allStats)

    file:write("Iteration number: ", j, "\n")
    for i = 1, #allStats do
        file:write(allStats[i][2].id, "\t", allStats[i][1].score, "\t", allStats[i][1].lines, "\n")
    end
    file:write('----\n')
    file:flush()

    for i = 1, 20 do
        table.remove(allStats)
    end

    -- 20 crossovers (first and second layer swap)
    local newNN = {}
    for i = 1, 20 do
        local rand1, rand2 = math.random(10), math.random(10)
        if rand1 < rand2 then
            table.insert(newNN, crossover(allStats[rand2][2], allStats[rand1][2]))
        else
            table.insert(newNN, crossover(allStats[rand1][2], allStats[rand2][2]))
        end
    end

    local n = {}
    for i = 1, #allStats do
        table.insert(n, allStats[i][2])
    end
    networks = TableConcat(n, newNN)

    if j % 20 == 0 then
        torch.save("checkpoint", {j, networks})
        file:write("Creating checkpoint\n")
        file:flush()
    end

    finalStats = allStats

    collectgarbage()
end

file:close()
