-- Render constants
local GAME_WIDTH = 192
local GAME_HEIGHT = 192
local RENDER_SCALE = 3

-- Game variables
local car
local puffs
local raceTrackData

-- Assets
local carImage
local raceTrackImage
local engineSounds
local crashSound

-- Initializes the game
function love.load()
  -- Load assets
  carImage = love.graphics.newImage('img/car.png')
  raceTrackImage = love.graphics.newImage('img/race-track.png')
  carImage:setFilter('nearest', 'nearest')
  raceTrackImage:setFilter('nearest', 'nearest')
  engineSounds = {
    love.audio.newSource('sfx/engine1.wav', 'static'),
    love.audio.newSource('sfx/engine2.wav', 'static'),
    love.audio.newSource('sfx/engine3.wav', 'static'),
    love.audio.newSource('sfx/engine4.wav', 'static')
  }
  crashSound = love.audio.newSource('sfx/crash.wav', 'static')

  -- Load race track data (from an image)
  raceTrackData = love.image.newImageData('img/race-track-data.png')

  -- Create the car and an array for puffs of exhaust
  puffs = {}
  car = createCar()
end

-- Updates the game state
function love.update(dt)
  -- Spawn a puff of exhaust every now and then
  car.puffTimer = car.puffTimer + dt
  if car.puffTimer > 1.25 - math.abs(car.speed) / 40 then
    car.puffTimer = 0.00
    table.insert(puffs, {
      x = car.x,
      y = car.y,
      timeToDisappear = 2.00
    })
  end

  -- Make some engine noises, with a higher pitch when the car is going faster
  car.engineNoiseTimer = car.engineNoiseTimer + dt
  if car.engineNoiseTimer > 0.17 then
    car.engineNoiseTimer = 0.00
    local speed = math.abs(car.speed)
    if speed > 30 then
      love.audio.play(engineSounds[4]:clone())
    elseif speed > 20 then
      love.audio.play(engineSounds[3]:clone())
    elseif speed > 10 then
      love.audio.play(engineSounds[2]:clone())
    else
      love.audio.play(engineSounds[1]:clone())
    end
  end

  -- Press down to brake
  if love.keyboard.isDown('down') then
    car.speed = math.max(car.speed - 20 * dt, -10)
  -- Press up to accelerate
  elseif love.keyboard.isDown('up') then
    car.speed = math.min(car.speed + 50 * dt, 40)
  -- Slow down when not accelerating
  else
    car.speed = car.speed * 0.98
  end

  -- Turn the car by pressing the left and right keys
  local turnSpeed = 3 * math.min(math.max(0, math.abs(car.speed) / 20), 1) - (car.speed > 20 and (car.speed - 20) / 20 or 0)
  if love.keyboard.isDown('left') then
    car.rotation = car.rotation - turnSpeed * dt
  end
  if love.keyboard.isDown('right') then
    car.rotation = car.rotation + turnSpeed * dt
  end
  car.rotation = (car.rotation + 2 * math.pi) % (2 * math.pi)

  -- Apply the car's velocity
  car.x = car.x + car.speed * -math.sin(car.rotation) * dt + car.bounceVelocityX * dt
  car.y = car.y + car.speed * math.cos(car.rotation) * dt + car.bounceVelocityY * dt

  -- Update the puffs of exhaust
  for i = #puffs, 1, -1 do
    local puff = puffs[i]
    puff.y = puff.y - 10 * dt
    puff.timeToDisappear = puff.timeToDisappear - dt
    if puff.timeToDisappear <= 0 then
      table.remove(puffs, i)
    end
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
    love.audio.play(crashSound:clone())
  end
  car.bounceVelocityX = car.bounceVelocityX * 0.90
  car.bounceVelocityY = car.bounceVelocityY * 0.90

  -- If the car ever gets out of bounds, reset it
  if car.x < 0 or car.y < 0 or car.x > GAME_WIDTH or car.y > GAME_HEIGHT then
    car = createCar()
  end
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
end

-- Creates the playable car
function createCar()
  return {
    x = 95,
    y = 28,
    bounceVelocityX = 0,
    bounceVelocityY = 0,
    speed = 0,
    rotation = math.pi / 2,
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
