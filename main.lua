local Sounds = require 'sounds'
local storage = require 'storage'
local cron = require 'cron'

if CASTLE_PREFETCH then
  CASTLE_PREFETCH({
    'sound.lua',
    'sounds.lua',
    'assets/snd/playing_loop_normal.mp3',
    'assets/snd/playing_loop_fast.mp3',
    'assets/snd/countdown_digit.mp3',
    'assets/snd/countdown_go.mp3',
    'assets/snd/engine1.mp3',
    'assets/snd/engine2.mp3',
    'assets/snd/engine3.mp3',
    'assets/snd/engine4.mp3',
    'assets/snd/crash.mp3',
    'assets/snd/finish_line.mp3',
    'assets/snd/finish_lap.mp3',
    'assets/snd/final_lap.mp3',
    'assets/snd/title_loop.mp3',
    'assets/snd/finish_race_won_jingle.mp3',
    'assets/snd/finish_race_lost_jingle.mp3',
    'assets/snd/score_screen_loop.mp3',
    'assets/snd/start_race_jingle.mp3',
    'assets/snd/final_lap_jingle.mp3',
    'assets/snd/launch_car.mp3',
    'assets/snd/hop.mp3',
    'assets/snd/slide.mp3',
  })
end

-- Render constants
local GAME_WIDTH = 192
local GAME_HEIGHT = 192
local RENDER_SCALE = 3

-- Game variables
local car
local puffs
local raceTrackData
local currLapNumber
local gameState
local raceTimer
local currLapTimer
local fastestLapTimer
local countdownDigit
local countdownTimer
local countdownLastDigitTime
local lapTimes
local raceStartTime
local TOTAL_NUM_LAPS = 3
local CAR_MAX_SPEED = 50
local clocks = {}
local hasUpdatedRaceData = false
local currFrameGhostData
local currRaceGhostData
local currRaceGhostSaveIntervalTimer
local GHOST_DATA_SAVE_INTERVAL = 0.2
local ghostDataToRaceAgainst = nil
local isAbleToStartRace = false

-- post stuff
local ghostDataFromPost
local ghostPostCreator

local hasPrintedGhostData = false -- TODO(jason): remove this debug line

-- open a ghost if one exists
function castle.postopened(post)
  ghostDataToRaceAgainst = post.data
  if post.creator ~= nil then
    ghostPostCreator = post.creator
  end
end

-- Assets
local carImage
local raceTrackImage

function fetchStoredData(ghostFetchedCallback)
  storage.getUserValue("fastestUserRaceTime", 100000)
  storage.getUserValue("fastestUserLapTime", 100000)
  storage.getUserValue("fastestUserGhostData", nil, ghostFetchedCallback)

  storage.getGlobalValue("fastestWorldRaceTime", 100000)
  storage.getGlobalValue("fastestWorldLapTime", 100000)
end

local function loadSounds()
  Sounds.launchCar = Sound:new("launch_car.mp3", 1)

  Sounds.engine1 = Sound:new("engine1.mp3", 6)
  Sounds.engine2 = Sound:new("engine2.mp3", 6)
  Sounds.engine3 = Sound:new("engine3.mp3", 6)
  Sounds.engine4 = Sound:new("engine4.mp3", 6)
  Sounds.crash = Sound:new("crash.mp3", 9)
  Sounds.engine1:setVolume(0.4)
  Sounds.engine2:setVolume(0.4)
  Sounds.engine3:setVolume(0.4)
  Sounds.engine4:setVolume(0.4)

  Sounds.playingLoopNormal = Sound:new('playing_loop_normal.mp3', 1)
  Sounds.playingLoopNormal:setVolume(1.0)
  Sounds.playingLoopNormal:setLooping(true)

  Sounds.playingLoopFast = Sound:new('playing_loop_fast.mp3', 1)
  Sounds.playingLoopFast:setVolume(1.0)
  Sounds.playingLoopFast:setLooping(true)

  Sounds.startRaceJingle = Sound:new('start_race_jingle.mp3', 1)

  Sounds.titleLoop = Sound:new('title_loop.mp3', 1)
  Sounds.titleLoop:setLooping(true)

  Sounds.finishRaceWonJingle = Sound:new('finish_race_won_jingle.mp3', 1)
  Sounds.finishRaceLostJingle = Sound:new('finish_race_lost_jingle.mp3', 1)
  Sounds.finishRaceWonJingle:setVolume(1.0)
  Sounds.finishRaceLostJingle:setVolume(1.0)

  Sounds.scoreScreenLoop = Sound:new('score_screen_loop.mp3', 1)
  Sounds.scoreScreenLoop:setVolume(1.0)
  Sounds.scoreScreenLoop:setLooping(true)

  Sounds.countdownDigit = Sound:new("countdown_digit.mp3", 2)
  Sounds.countdownGo = Sound:new("countdown_go.mp3", 1)

  Sounds.hop = Sound:new("hop.mp3", 1)
  Sounds.slide = Sound:new("slide.mp3", 1)

  Sounds.finishLap = Sound:new("finish_lap.mp3", 1)
  Sounds.finalLapJingle = Sound:new("final_lap_jingle.mp3", 1)
  Sounds.finishLine = Sound:new("finish_line.mp3", 1)
end

-- Initializes the game
function love.load()

  -- Load assets
  loadSounds()
  carImage = love.graphics.newImage('img/car.png')
  raceTrackImage = love.graphics.newImage('img/race-track.png')
  carImage:setFilter('nearest', 'nearest')
  raceTrackImage:setFilter('nearest', 'nearest')
  raceTrackData = love.image.newImageData('img/race-track-data.png')

  puffs = {}
  car = createCar()

  Sounds.titleLoop:play()

  gameState = "title"

  fetchStoredData(function()
    if storage.fastestUserGhostData ~= nil and ghostDataToRaceAgainst == nil then
      print("Using User's Fastest Ghost Data!")
      ghostDataToRaceAgainst = storage.fastestUserGhostData
    elseif ghostDataToRaceAgainst ~= nil then
      print("Using post's ghost data!")
      currFrameGhostData = ghostDataToRaceAgainst['raceData'][1]
    end
    isAbleToStartRace = true
  end)

  -- Careful: below line will reset user and world scoreboard
  --resetAllStoredData()
end

function resetAllStoredData()
  storage.setUserValue("fastestUserRaceTime", 99999)
  storage.setUserValue("fastestUserLapTime", 99999)
  storage.setUserValue("fastestUserGhostData", nil)
  storage.setGlobalValue("fastestWorldRaceTime", 99999)
  storage.setGlobalValue("fastestWorldLapTime", 99999)
end

-- Setup the state of the race
function restartRace()
  puffs = {}
  car = createCar()

  currRaceGhostData = {}
  currRaceGhostData['lapTimes'] = {}
  currRaceGhostData['raceData'] = {}
  -- init this larger so that it saves ghost data on first frame
  currRaceGhostSaveIntervalTimer = GHOST_DATA_SAVE_INTERVAL + 1.0

  lapTimes = {}
  currLapNumber = 0

  raceTimer = 0
  currLapTimer = 0
  fastestLapTimer = 10000000
  countdownTimer = 0
  countdownLastDigitTime = love.timer.getTime()
  countdownDigit = 3

  Sounds.startRaceJingle:play()

  -- clear the clocks
  for k,v in pairs(clocks) do
    clocks[k] = nil
  end

  -- reset ghost data
  if ghostDataToRaceAgainst ~= nil then
    currFrameGhostData = ghostDataToRaceAgainst['raceData'][1]
  end

  gameState = "race_intro"
end

function love.keypressed(key, scancode, isrepeat)
  if gameState == 'title' and key == 'up' and isAbleToStartRace then
    Sounds.titleLoop:stop()
    restartRace()
  elseif gameState == 'racing' and key == 'space' then
    car.hopSlideTimer = 0.0
    Sounds.hop:play()
  elseif gameState == 'racing' and key == 'r' then
    Sounds.playingLoopNormal:stop()
    Sounds.playingLoopFast:stop()
    restartRace()
  elseif gameState == 'score_screen' and key == 'up' then
    Sounds.scoreScreenLoop:stop()
    restartRace()
  elseif gameState == 'score_screen' and key == 'p' then
    network.async(function()
      castle.post.create {
        message = 'See if you can beat my ghost!',
        media = 'capture',
        data = {
          currRaceGhostData
        }
      }
    end)
  end
end

function love.keyreleased(key, scancode)
  if gameState == 'racing' and key == 'space' then
    car.isHopSliding = -1.0
  end
end

-- Spawn a puff of exhaust every now and then
local function spawnExhaustPuffs(dt)
  car.puffTimer = car.puffTimer + dt
  if car.puffTimer > 1.25 - math.abs(car.speed) / CAR_MAX_SPEED then
    car.puffTimer = 0.00
    table.insert(puffs, {
      x = car.x,
      y = car.y,
      timeToDisappear = 2.00
    })
  end
end

-- Update the car's exhaust puffs
local function updateExhaustPuffs(dt)
  -- Exhaust puffs
  for i = #puffs, 1, -1 do
    local puff = puffs[i]
    puff.y = puff.y - 8 * dt
    puff.timeToDisappear = puff.timeToDisappear - dt
    if puff.timeToDisappear <= 0 then
      table.remove(puffs, i)
    end
  end
end

-- Move the car, keeping track of its position in the previous frame
local function updateCarPosition(dt)
  car.prevX = car.x
  car.prevY = car.y
  car.x = car.x + car.speed * -math.sin(car.rotation) * dt + car.bounceVelocityX * dt
  car.y = car.y + car.speed * math.cos(car.rotation) * dt + car.bounceVelocityY * dt
end

-- Make some engine noises, with a higher pitch when the car is going faster
local function makeCarEngineNoise(dt)
  car.engineNoiseTimer = car.engineNoiseTimer + dt
  if car.engineNoiseTimer > 0.17 then
    car.engineNoiseTimer = 0.00
    local speed = math.abs(car.speed)
    if speed > 30 then
      Sounds.engine4:play()
    elseif speed > 20 then
      Sounds.engine3:play()
    elseif speed > 10 then
      Sounds.engine2:play()
    else
      Sounds.engine1:play()
    end
  end
end

local function updateClocks(dt)
  for k,v in pairs(clocks) do
    clocks[k]:update(dt)
  end
end

-- Debug Helper
function printRaceData(data)
  for i,v in ipairs(data) do
    print('-------------')
    print('t: '..data[i].t)
    print('x: '..data[i].x)
    print('y: '..data[i].y)
    print('r: '..data[i].rotation)
  end
end

-- Updates the game state
function love.update(dt)
  updateClocks(dt)

  spawnExhaustPuffs(dt)
  updateExhaustPuffs(dt)

  -- if storage.fastestUserGhostData ~= nil then
  --   if hasPrintedGhostData == false then
  --     hasPrintedGhostData = true
  --     print("User's Fastest Ghost Found!")
  --     printRaceData(storage.fastestUserGhostData['raceData'])
  --     currFrameGhostData = storage.fastestUserGhostData['raceData'][1]
  --   end
  -- end

  -- Countdown at start of race
  if gameState == "race_intro" then
    if clocks['raceIntroDuration'] == nil then
      clocks['raceIntroDuration'] = cron.after(3.0, function()
        clocks['raceIntroDuration'] = nil
        Sounds.countdownDigit:play()
        gameState = "countdown"
      end)
    end
  elseif gameState == "countdown" then
    makeCarEngineNoise(dt)
    updateExhaustPuffs(dt)
    countdownTimer = love.timer.getTime() - countdownLastDigitTime
    if countdownTimer > 1.4 then
      countdownDigit = countdownDigit - 1
      if countdownDigit == 0 then
        Sounds.countdownGo:play()
        Sounds.playingLoopNormal:play()
        Sounds.launchCar:play()
        currLapStartTime = love.timer.getTime()
        raceStartTime = love.timer.getTime()
        -- TODO(jason): make it so speed boost happens if up is pressed at perfect time
        car.speed = CAR_MAX_SPEED
        gameState = "racing"
      else
        Sounds.countdownDigit:play()
      end
      countdownLastDigitTime = love.timer.getTime()
      countdownTimer = 0
    end

  -- when showing scores after race
  elseif gameState == "score_screen" then
    -- TODO(jason): update score screen

    -- TODO(jason): show instructions for making a post with the ghost
    -- Maybe: If they beat the ghost's time, bring up the post screen automatically?

  -- When race is finished
  elseif gameState == "finished" then

    if hasUpdatedRaceData == false then
      hasUpdatedRaceData = true
      -- print("raceTimer: "..raceTimer)
      -- print("fastesLapTimer: "..fastestLapTimer)
      -- print("storage.fastestUserRaceTime: "..storage.fastestUserRaceTime)
      -- print("storage.fastestUserLapTime: "..storage.fastestUserLapTime)
      -- print("storage.fastestWorldRaceTime: "..storage.fastestWorldRaceTime)
      -- print("storage.fastestWorldLapTime: "..storage.fastestWorldLapTime)

      -- TODO(jason): celebrate new user/global PRs somehow...
      if raceTimer < storage.fastestUserRaceTime then
        storage.setUserValue("fastestUserRaceTime", raceTimer)
        storage.setUserValue("fastestUserGhostData", currRaceGhostData)
      end

      if fastestLapTimer < storage.fastestUserLapTime then
        storage.setUserValue("fastestUserLapTime", fastestLapTimer)
      end

      if raceTimer < storage.fastestWorldRaceTime then
        storage.setGlobalValue("fastestWorldRaceTime", raceTimer)
      end

      if fastestLapTimer < storage.fastestWorldLapTime then
        storage.setGlobalValue("fastestWorldLapTime", fastestLapTimer)
      end
    end

    -- slowly stop car after race
    updateCarPosition(dt)
    car.speed = car.speed * 0.98

    --TODO(jason): play diff sound depending upon whether ghost beaten or not
    if clocks['finishRaceWonJingle'] == nil then
      clocks['finishRaceWonJingle'] = cron.after(2, function() 
        Sounds.finishRaceWonJingle:play()
        if clocks['goToScoreScreen'] == nil then
          clocks['goToScoreScreen'] = cron.after(4.3, function()
            Sounds.scoreScreenLoop:play()
            gameState = "score_screen"
          end)
        end
      end)
    end
    
  -- When player is racing
  elseif gameState == "racing" then

    if ghostDataToRaceAgainst ~= nil then
      for i,v in ipairs(ghostDataToRaceAgainst['raceData']) do
        if raceTimer > ghostDataToRaceAgainst['raceData'][i].t then
          -- TODO(jason): Do linear interpolation between time t and the previous time
          -- to compute a position x,y, and rotation r, at which to render the ghost
          -- instead of passing currGhostDataIndex to Draw, store the interpolated data for this frame

          -- if end of race, mark ghost data with 'done' sentinel so it won't render
          if i == #ghostDataToRaceAgainst['raceData'] then
            currFrameGhostData = 'done'
          else
            -- else lerp between this ghost frame and next ghost frame
            local a = ghostDataToRaceAgainst['raceData'][i]
            local b = ghostDataToRaceAgainst['raceData'][i+1]
            local aWeight = (b.t - raceTimer) / GHOST_DATA_SAVE_INTERVAL
            local bWeight = 1.0 - aWeight
            currFrameGhostData = {
              t = raceTimer,
              x = a.x * aWeight + b.x * bWeight,
              y = a.y * aWeight + b.y * bWeight,
              rotation = a.rotation -- a.rotation * aWeight + b.rotation * bWeight, -- rotation bugged prob due to trig domain issue
            }
          end
        end
      end
    end

    makeCarEngineNoise(dt)

    -- Control the car with arrow keys
    if love.keyboard.isDown('down') then
      car.speed = math.max(car.speed - 20 * dt, -10)
    elseif love.keyboard.isDown('up') then
      car.speed = math.min(car.speed + 50 * dt, CAR_MAX_SPEED)
    else
      car.speed = car.speed * 0.985
    end

    local turnSpeed = 3.8 * math.min(math.max(0, math.abs(car.speed) / 20), 1) - (car.speed > 20 and (car.speed - 20) / 20 or 0)
    if love.keyboard.isDown('left') then
      car.rotation = car.rotation - turnSpeed * dt
    end
    if love.keyboard.isDown('right') then
      car.rotation = car.rotation + turnSpeed * dt
    end
    car.rotation = (car.rotation + 2 * math.pi) % (2 * math.pi)

    updateCarPosition(dt)

    -- save one ghost data point
    if currRaceGhostSaveIntervalTimer > GHOST_DATA_SAVE_INTERVAL then
      currRaceGhostData['raceData'][#currRaceGhostData['raceData'] + 1] = {
        t = raceTimer,
        x = car.x,
        y = car.y,
        rotation = car.rotation,
      }

      currRaceGhostSaveIntervalTimer = 0.0
    end

    -- Check what terrain the car is currently on by looking at the race track data image
    local pixelX = math.min(math.max(0, math.floor(car.x)), 191)
    local pixelY = math.min(math.max(0, math.floor(car.y)), 191)
    local r, g, b = raceTrackData:getPixel(pixelX, pixelY)
    local isInBarrier = r > 0 -- red means barriers
    local isInRoughTerrain = b > 0 -- blue means rough terrain

    -- If the car runs off the track, it slows down
    if isInRoughTerrain then
      car.speed = car.speed * 0.95
    end

    -- If the car becomes lodged in a barrier, bounce it away
    if isInBarrier then
      local vx = car.speed * -math.sin(car.rotation) + car.bounceVelocityX
      local vy = car.speed * math.cos(car.rotation) + car.bounceVelocityY
      car.bounceVelocityX = -2 * vx
      car.bounceVelocityY = -2 * vy
      car.speed = car.speed * 0.50
      Sounds.crash:play()
    end
    car.bounceVelocityX = car.bounceVelocityX * 0.90
    car.bounceVelocityY = car.bounceVelocityY * 0.90

    -- If the car ever gets out of bounds, reset it
    if car.x < 0 or car.y < 0 or car.x > GAME_WIDTH or car.y > GAME_HEIGHT then
      car = createCar()
    end

    -- Handle going backwards across finish line
    if car.x > 108 and car.prevX <= 108 and car.y < 50 and car.y > 0 then
      wentBackwardsOverLine = true
    end

    -- When the car finishes a lap
    if car.x < 108 and car.prevX >= 108 and car.y < 50 and car.y > 0 then
      if wentBackwardsOverLine then
        wentBackwardsOverLine = false
      else
        if currLapNumber > 0 then 
          if currLapTimer < fastestLapTimer then
            fastestLapTimer = currLapTimer
          end
          lapTimes[currLapNumber] = currLapTimer
          currRaceGhostData['lapTimes'][currLapNumber] = currLapTimer
          print("Lap "..currLapNumber.." time: "..currLapTimer)
        end

        currLapTimer = 0.0

        currLapNumber = currLapNumber + 1

        if currLapNumber > TOTAL_NUM_LAPS then
          -- save one last frame of ghost data
          currRaceGhostData['raceData'][#currRaceGhostData['raceData'] + 1] = {
            t = raceTimer,
            x = car.x,
            y = car.y,
            rotation = car.rotation,
          }

          currRaceGhostData['raceTime'] = raceTimer

          -- Race completed
          Sounds.finishLine:play()
          Sounds.playingLoopFast:stop()
          gameState = "finished"
        else
          -- Lap completed
          if currLapNumber == TOTAL_NUM_LAPS then
            -- Final Lap
            Sounds.playingLoopNormal:stop()
            clocks['finalLapMusicSpeedIncreaseDelay'] = cron.after(2.1, function()
              Sounds.playingLoopFast:play()
              clocks['finalLapMusicSpeedIncreaseDelay'] = nil
            end)
            Sounds.finalLapJingle:play()
          elseif currLapNumber > 1 then
            -- All Other Laps
            Sounds.finishLap:play()
          end
        end
      end
    end
    car.hopSlideTimer = car.hopSlideTimer + dt
    currRaceGhostSaveIntervalTimer = currRaceGhostSaveIntervalTimer + dt
    raceTimer = raceTimer + dt
    currLapTimer = currLapTimer + dt
  end
end

local function getTimeString(t)
  local minutes = string.format("%02d", math.floor(t/60))
  local seconds = string.format("%02d", math.floor(t - minutes * 60))
  local ms = string.format("%02d", math.floor((t * 1000) - math.floor(t) * 1000))
  return minutes.."\' "..seconds.."\" "..ms
end

-- Renders the game
function love.draw()
  -- Scale and crop the screen
  love.graphics.setScissor(0, 0, RENDER_SCALE * GAME_WIDTH, RENDER_SCALE * GAME_HEIGHT)
  love.graphics.scale(RENDER_SCALE, RENDER_SCALE)
  love.graphics.clear(0, 0, 0)
  love.graphics.setColor(1, 1, 1)

  -- Draw the race track
  love.graphics.draw(raceTrackImage, 0, 0)

  -- Draw the car
  local radiansPerSprite = 2 * math.pi / 16
  local sprite = math.floor((car.rotation + radiansPerSprite / 2) / radiansPerSprite) + 1
  if car.rotation >= math.pi then
    sprite = 18 - sprite
  end
  drawSprite(carImage, 12, 12, sprite, car.x - 6, car.y - 6, car.rotation >= math.pi)

  -- Draw the puffs of exhaust coming out of the car
  love.graphics.setColor(142 / 255, 92 / 255, 111 / 255)
  for _, puff in ipairs(puffs) do
    love.graphics.rectangle('fill', puff.x - 1, puff.y - 1, 2, 2)
  end

  if gameState == 'countdown' or gameState == "racing" then

    -- Draw the Ghost
    if ghostDataToRaceAgainst ~= nil and currFrameGhostData ~= 'done' then
      -- TODO(jason): make ghost flash really subtly?
        -- (maybe set alpha to 0 for last 50 ms of every second?)

      love.graphics.setColor(1,1,1,0.38) -- ghost is partially transparent

      local ghostSprite = math.floor((currFrameGhostData.rotation + radiansPerSprite / 2) / radiansPerSprite) + 1
      if currFrameGhostData.rotation >= math.pi then
        ghostSprite = 18 - ghostSprite
      end
      drawSprite(carImage, 12, 12, ghostSprite, currFrameGhostData.x - 6, currFrameGhostData.y - 6, currFrameGhostData.rotation >= math.pi)
    end

    -- Traffic Light for Countdown
    if raceTimer < 1.5 then
      if countdownDigit == 3 then
        love.graphics.setColor(.4,.4,.4,1.0)
        love.graphics.circle('fill', 64, 4, 3, 32)
        love.graphics.circle('fill', 72, 4, 3, 32)
        love.graphics.circle('fill', 80, 4, 3, 32)
      elseif countdownDigit == 2 then
        love.graphics.setColor(.4,1.0,.4,1.0)
        love.graphics.circle('fill', 64, 4, 3, 32)
        love.graphics.setColor(.4,.4,.4,1.0)
        love.graphics.circle('fill', 72, 4, 3, 32)
        love.graphics.circle('fill', 80, 4, 3, 32)
      elseif countdownDigit == 1 then
        love.graphics.setColor(.4,1.0,.4,1.0)
        love.graphics.circle('fill', 64, 4, 3, 32)
        love.graphics.circle('fill', 72, 4, 3, 32)
        love.graphics.setColor(.4,.4,.4,1.0)
        love.graphics.circle('fill', 80, 4, 3, 32)
      elseif countdownDigit == 0 then
        love.graphics.setColor(.4,1.0,.4,1.0)
        love.graphics.circle('fill', 64, 4, 3, 32)
        love.graphics.circle('fill', 72, 4, 3, 32)
        love.graphics.setColor(1.0,.4,.4,1.0)
        love.graphics.circle('fill', 80, 4, 3, 32)
      end
    end

    love.graphics.setColor(1,1,1,1)

    -- Time
    love.graphics.print(getTimeString(raceTimer), 100, 1, 0, 0.5, 0.5)

    -- Lap
    love.graphics.print("Lap "..math.max(1, currLapNumber).." / "..TOTAL_NUM_LAPS, 146, 1, 0, 0.5, 0.5)
  end

  if gameState == 'score_screen' then
    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle('fill', 0, 0, RENDER_SCALE * GAME_WIDTH, RENDER_SCALE * GAME_HEIGHT)
    love.graphics.setColor(1,1,1,1)
    love.graphics.print(getTimeString(raceTimer), 43, 90, 0, 1.5, 1.5)

    for i,v in pairs(lapTimes) do
      love.graphics.print("Lap "..i..": "..getTimeString(lapTimes[i]), 43, 100 + i * 10, 0, 0.7, 0.7)
    end

    love.graphics.setColor(1,1,1,1)
    love.graphics.print('Press up arrow to race again', 4,2, 0, .4, .4)

    love.graphics.setColor(1,1,1,1)
    love.graphics.print('Press P to post your ghost', 43, 170, 0, 0.7, 0.7)
  end

  if gameState == 'title' then
    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle('fill', 0, 0, RENDER_SCALE * GAME_WIDTH, RENDER_SCALE * GAME_HEIGHT)

    if isAbleToStartRace then
      love.graphics.setColor(1,1,1,1)
      love.graphics.print('Press up arrow to start race', 32, 98, 0, .8, .8)
    end

    -- world high scores
    if storage.fastestWorldRaceTime < 99999 then
      love.graphics.print('World fastest race: '..getTimeString(storage.fastestWorldRaceTime), 4, 2, 0, .4, .4)
    end
    if storage.fastestWorldLapTime < 99999 then 
      love.graphics.print('World fastest lap  : '..getTimeString(storage.fastestWorldLapTime), 4, 8, 0, .4, .4)
    end

    -- your high scores
    if storage.fastestUserRaceTime < 99999 then 
      love.graphics.print('Your fastest race: '..getTimeString(storage.fastestUserRaceTime), 4, 16, 0, .4, .4)
    end
    if storage.fastestUserLapTime < 99999 then 
      love.graphics.print('Your fastest lap  : '..getTimeString(storage.fastestUserLapTime), 4, 22, 0, .4, .4)
    end

    -- TODO(jason): draw avatar of challenger
    -- TODO(jason): draw time of challenger's ghost
    --love.graphics.print(getTimeString(ghostRaceTime), 45, 90, 0, 1.5, 1.5)
  end
end

-- Creates the playable car
function createCar()
  return {
    x = 128,
    y = 32,
    prevX = 128,
    prevY = 32,
    bounceVelocityX = 0,
    bounceVelocityY = 0,
    speed = 0,
    rotation = math.pi / 2,
    hopSlideTimer = -1.0,
    engineNoiseTimer = 0.00,
    puffTimer = 0.00
  }
end

-- Draws a sprite from a sprite sheet, spriteNum=1 is the upper-leftmost sprite
function drawSprite(spriteSheetImage, spriteWidth, spriteHeight, sprite, x, y, flipHorizontal, flipVertical, rotation)
  local width, height = spriteSheetImage:getDimensions()
  local numColumns = math.floor(width / spriteWidth)
  local col, row = (sprite - 1) % numColumns, math.floor((sprite - 1) / numColumns)
  love.graphics.draw(spriteSheetImage,
    love.graphics.newQuad(spriteWidth * col, spriteHeight * row, spriteWidth, spriteHeight, width, height),
    x + spriteWidth / 2, y + spriteHeight / 2,
    rotation or 0,
    flipHorizontal and -1 or 1, flipVertical and -1 or 1,
    spriteWidth / 2, spriteHeight / 2)
end
