-- @description REAPER Scheduled Recording
-- @version 1.0
-- @date 2026-04-02
-- @about
-- Scheduled recording with optional duration.
-- After closing the window the scheduled recording duration will be ignored.
--------------------------------------------------------------------

local version = 1.0
local WIN_W, WIN_H = 500, 340
gfx.init("REAPER Scheduled Recording" .. version, WIN_W, WIN_H, 0)


gfx.setfont(1, "Calibri", 16)      -- inputs and buttons
gfx.setfont(2, "Calibri", 24, "b") -- header and clock
gfx.setfont(3, "Calibri", 18)      -- status and annotations

local P = {
  bg = {0.10, 0.10, 0.14},
  panel = {0.13, 0.13, 0.18},
  field = {0.16, 0.17, 0.23},
  field_a = {0.19, 0.34, 0.60},
  bdr = {0.30, 0.30, 0.42},
  bdr_a = {0.40, 0.64, 1.00},
  txt = {0.90, 0.92, 1.00},
  lbl = {0.48, 0.54, 0.68},
  btn = {0.17, 0.39, 0.70},
  btn_hov = {0.25, 0.51, 0.88},
  btn_dis = {0.17, 0.17, 0.23},
  btn_red = {0.52, 0.14, 0.14},
  btn_redh = {0.72, 0.21, 0.21},
  ok = {0.28, 0.98, 0.48},
  err = {1.00, 0.33, 0.33},
  rec = {1.00, 0.27, 0.27},
  def = {0.58, 0.64, 0.78},
}

local function col(c) gfx.set(c[1], c[2], c[3]) end
local function fill(x,y,w,h,c) col(c); gfx.rect(x,y,w,h,1) end
local function strk(x,y,w,h,c) col(c); gfx.rect(x,y,w,h,0) end

-- Field layout
local FH = 26
local FY1 = 124
local FY2 = 198

local DX_Y, DX_M, DX_D = 32, 122, 182
local TX_H, TX_M, TX_S = 32, 88, 144
local RX_H, RX_M, RX_S = 270, 326, 382

local fields = {
  {id="year", x=DX_Y, y=FY1, w=68, ml=4, hint="YYYY"},
  {id="mon",  x=DX_M, y=FY1, w=40, ml=2, hint="MM"},
  {id="day",  x=DX_D, y=FY1, w=40, ml=2, hint="DD"},
  {id="t_h",  x=TX_H, y=FY2, w=38, ml=2, hint="HH"},
  {id="t_m",  x=TX_M, y=FY2, w=38, ml=2, hint="MM"},
  {id="t_s",  x=TX_S, y=FY2, w=38, ml=2, hint="SS"},
  {id="d_h",  x=RX_H, y=FY2, w=38, ml=2, hint="HH"},
  {id="d_m",  x=RX_M, y=FY2, w=38, ml=2, hint="MM"},
  {id="d_s",  x=RX_S, y=FY2, w=38, ml=2, hint="SS"},
}
for i, f in ipairs(fields) do f.h = FH; f.idx = i end

local fmap = {}
for _, f in ipairs(fields) do fmap[f.id] = f end

local vals = {}
for _, f in ipairs(fields) do vals[f.id] = "" end

local field_limits = {
  year = {min=2000, max=9999, step=1},
  mon  = {min=1, max=12, step=1},
  day  = {min=1, max=31, step=1},
  t_h  = {min=0, max=23, step=1},
  t_m  = {min=0, max=59, step=1},
  t_s  = {min=0, max=59, step=1},
  d_h  = {min=0, max=99, step=1},
  d_m  = {min=0, max=59, step=1},
  d_s  = {min=0, max=59, step=1},
}

-- State
local active_id = nil
local scheduled = false
local sched_ts = nil
local stop_ts = nil
local rec_on = false
local msg = "Set date/time and click Schedule."
local msg_col = P.def
local last_cap = 0

-- ==================== HELPERS ====================
local function hms(secs)
  secs = math.max(0, math.floor(secs))
  return ("%02d:%02d:%02d"):format(math.floor(secs/3600), math.floor((secs%3600)/60), secs%60)
end

local function is_rec()
  return (reaper.GetPlayState() & 4) ~= 0
end

local function fill_dt(t)
  vals.year = ("%04d"):format(t.year)
  vals.mon  = ("%02d"):format(t.month)
  vals.day  = ("%02d"):format(t.day)
  vals.t_h  = ("%02d"):format(t.hour)
  vals.t_m  = ("%02d"):format(t.min)
  vals.t_s  = ("%02d"):format(t.sec)
end

local function adjust_field(id, delta)
  local f = fmap[id]
  if not f or not field_limits[id] then return end
  local lim = field_limits[id]
  local v = tonumber(vals[id]) or lim.min

  v = v + delta * lim.step

  if id == "year" then
    v = math.max(lim.min, math.min(lim.max, v))
  else
    local range = lim.max - lim.min + 1
    v = ((v - lim.min) % range) + lim.min
  end

  vals[id] = string.format("%0" .. f.ml .. "d", v)
end

local function advance_time(minutes)
  local y,mo,d = tonumber(vals.year), tonumber(vals.mon), tonumber(vals.day)
  local h,m,s = tonumber(vals.t_h) or 0, tonumber(vals.t_m) or 0, tonumber(vals.t_s) or 0
  local ts = os.time{year=y, month=mo, day=d, hour=h, min=m, sec=s}
  ts = ts + minutes * 60
  local nt = os.date("*t", ts)
  vals.year = ("%04d"):format(nt.year)
  vals.mon  = ("%02d"):format(nt.month)
  vals.day  = ("%02d"):format(nt.day)
  vals.t_h  = ("%02d"):format(nt.hour)
  vals.t_m  = ("%02d"):format(nt.min)
  vals.t_s  = ("%02d"):format(nt.sec)
end

local function set_current_time()
  local t = os.date("*t")
  vals.t_h = ("%02d"):format(t.hour)
  vals.t_m = ("%02d"):format(t.min)
  vals.t_s = ("%02d"):format(t.sec)
end

local function try_schedule()
  local y, mo, d = tonumber(vals.year), tonumber(vals.mon), tonumber(vals.day)
  local h, m, s = tonumber(vals.t_h), tonumber(vals.t_m), tonumber(vals.t_s)
  local dh, dm, ds = tonumber(vals.d_h) or 0, tonumber(vals.d_m) or 0, tonumber(vals.d_s) or 0

  if not (y and mo and d and h and m and s) then
    msg = "Please fill all date/time fields"; msg_col = P.err; return
  end

  local dur = dh*3600 + dm*60 + ds
  local ts = os.time{year=y, month=mo, day=d, hour=h, min=m, sec=s}

  if ts <= os.time() then
    msg = "Start time is in the past :("; msg_col = P.err; return
  end

  sched_ts = ts
  stop_ts = dur > 0 and (ts + dur) or nil
  scheduled = true
  rec_on = false

  local dur_txt = dur > 0 and (" (duration "..hms(dur)..")") or " (no auto-stop)"
  msg = ("Waiting — start at %s%s"):format(os.date("%Y-%m-%d %H:%M:%S", ts), dur_txt)
  msg_col = P.ok
end

local function do_cancel()
  if rec_on and is_rec() then reaper.Main_OnCommand(1016, 0) end
  scheduled = false; rec_on = false
  sched_ts = nil; stop_ts = nil
  msg = "Schedule cancelled"; msg_col = P.def
end

-- ==================== DRAWING ====================
local function draw_field(f)
  local act = (active_id == f.id)
  fill(f.x, f.y, f.w, f.h, act and P.field_a or P.field)
  strk(f.x, f.y, f.w, f.h, act and P.bdr_a or P.bdr)
  gfx.setfont(1)
  local text = vals[f.id]
  local ghost = (text == "")
  col(ghost and P.bdr or P.txt)
  local disp = ghost and f.hint or text
  local tw = gfx.measurestr(disp)
  gfx.x = f.x + (f.w - tw)//2
  gfx.y = f.y + (f.h - gfx.texth)//2
  gfx.drawstr(disp)

  if act and not ghost and math.floor(reaper.time_precise()*2)%2 == 0 then
    col(P.txt)
    gfx.x = f.x + (f.w + tw)//2 + 2
    gfx.y = f.y + 4
    gfx.drawstr("|")
  end
end

local function draw_btn(x, y, w, h, lbl, en, red)
  local mx, my = gfx.mouse_x, gfx.mouse_y
  local hov = mx >= x and mx <= x+w and my >= y and my <= y+h
  local bg = not en and P.btn_dis or (red and (hov and P.btn_redh or P.btn_red) or (hov and P.btn_hov or P.btn))
  fill(x, y, w, h, bg)
  strk(x, y, w, h, en and P.bdr_a or P.bdr)
  gfx.setfont(1); col(en and P.txt or P.bdr)
  local tw = gfx.measurestr(lbl)
  gfx.x = x + (w - tw)//2
  gfx.y = y + (h - gfx.texth)//2
  gfx.drawstr(lbl)
end

local function clicked(x, y, w, h)
  local mx, my = gfx.mouse_x, gfx.mouse_y
  return mx >= x and mx <= x+w and my >= y and my <= y+h
     and (gfx.mouse_cap & 1) == 1 and (last_cap & 1) == 0
end

-- Main loop
local function loop()
  if scheduled then
    local now = os.time()
    if not rec_on and now >= sched_ts then
      if not is_rec() then reaper.Main_OnCommand(1013, 0) end
      rec_on = true
      msg = stop_ts and "● Recording in progress…" or "● Recording in progress… (manual stop)"
      msg_col = P.rec
    end

    if rec_on and stop_ts and now >= stop_ts then
      reaper.Main_OnCommand(1016, 0)
      scheduled = false; rec_on = false
      msg = "✓ Recording finished successfully"; msg_col = P.ok
    end
  end

  -- Background
  fill(0, 0, WIN_W, WIN_H, P.bg)
  fill(0, 0, WIN_W, 46, P.panel)

  gfx.setfont(2); col(P.txt)
  local ttl = "REAPER Scheduled Recording"
  gfx.x = (WIN_W - gfx.measurestr(ttl))//2; gfx.y = 14
  gfx.drawstr(ttl)

  -- Live clock
  gfx.setfont(2)
  local today_str = "Now: " .. os.date("%Y-%m-%d")
--  gfx.x = WIN_W - gfx.measurestr(today_str) - 15
--  gfx.y = 72
  gfx.x = WIN_W - gfx.measurestr(today_str) - 90
  gfx.y = 72
  col(P.txt)
  gfx.drawstr(today_str)

  gfx.setfont(2)
  local clock_str = os.date("%H:%M:%S")
  gfx.x = WIN_W - gfx.measurestr(clock_str) - 15
  gfx.y = 72
  gfx.drawstr(clock_str)

  -- Warning text
  gfx.setfont(3); col(P.err)
  local warn = "After closing the window, the scheduled recording duration\nwill be ignored."
  gfx.x = 32; gfx.y = 44
  gfx.drawstr(warn)

  -- Labels
  gfx.setfont(3); col(P.lbl)
  gfx.x = DX_Y; gfx.y = 96;  gfx.drawstr("Start Date YYYY / MM / DD")
  gfx.x = TX_H; gfx.y = 170; gfx.drawstr("Start Time HH : MM : SS")
  gfx.x = RX_H; gfx.y = 170; gfx.drawstr("Duration HH : MM : SS (optional)")

  -- Separators
  gfx.setfont(1); col(P.lbl)
  gfx.x = DX_Y + 68 + 8; gfx.y = FY1 + 5; gfx.drawstr("/")
  gfx.x = DX_M + 40 + 7; gfx.y = FY1 + 5; gfx.drawstr("/")
  gfx.x = TX_H + 38 + 7; gfx.y = FY2 + 5; gfx.drawstr(":")
  gfx.x = TX_M + 38 + 7; gfx.y = FY2 + 5; gfx.drawstr(":")
  gfx.x = RX_H + 38 + 7; gfx.y = FY2 + 5; gfx.drawstr(":")
  gfx.x = RX_M + 38 + 7; gfx.y = FY2 + 5; gfx.drawstr(":")

  for _, f in ipairs(fields) do draw_field(f) end

  -- Button 🕒
  local clock_btn_x = TX_S + 48
  local clock_btn_y = FY2
  draw_btn(clock_btn_x, clock_btn_y, 54, 26, "< NOW", true)

  -- Status bar
  local SY = 232
  fill(15, SY, WIN_W-30, 38, P.panel)
  strk(15, SY, WIN_W-30, 38, P.bdr)

  local disp = msg
  if scheduled and not rec_on and sched_ts then
    local rem = sched_ts - os.time()
    if rem > 0 then
      local start_str = os.date("%H:%M:%S", sched_ts)
      disp = stop_ts and ("Starts in "..hms(rem).." → "..start_str) or ("Starts in "..hms(rem).." → "..start_str.." (no auto-stop)")
    end
  elseif scheduled and rec_on then
    disp = stop_ts and ("● Recording — stops in "..hms(stop_ts - os.time())) or "● Recording… (manual stop)"
  end

  gfx.setfont(3); col(msg_col)
  gfx.x = (WIN_W - gfx.measurestr(disp))//2
  gfx.y = SY + 13
  gfx.drawstr(disp)

  -- Buttons
  local BY = 280
  if not scheduled then
    draw_btn(15, BY, 85, 28, "+1 min", true)
    draw_btn(108, BY, 85, 28, "+5 min", true)
    draw_btn(WIN_W-120, BY, 105, 28, "▶ Schedule", true)
  else
    draw_btn(WIN_W-120, BY, 105, 28, "■ Cancel", true, true)
  end

  -- Mouse & keyboard handling
  local cap = gfx.mouse_cap
  local mx, my = gfx.mouse_x, gfx.mouse_y

  if (cap & 1) == 1 and (last_cap & 1) == 0 then
    active_id = nil
    for _, f in ipairs(fields) do
      if mx >= f.x and mx <= f.x+f.w and my >= f.y and my <= f.y+f.h then
        active_id = f.id
        break
      end
    end

    -- Clock button
    if mx >= clock_btn_x and mx <= clock_btn_x + 34 and my >= clock_btn_y and my <= clock_btn_y + 26 then
      set_current_time()
    end
  end

  if gfx.mouse_wheel ~= 0 then
    local delta = gfx.mouse_wheel > 0 and 1 or -1
    for _, f in ipairs(fields) do
      if mx >= f.x and mx <= f.x+f.w and my >= f.y and my <= f.y+f.h then
        adjust_field(f.id, delta)
        active_id = f.id
        gfx.mouse_wheel = 0
        break
      end
    end
  end

  if not scheduled then
    if clicked(15, BY, 85, 28) then advance_time(1) end
    if clicked(108, BY, 85, 28) then advance_time(5) end
    if clicked(WIN_W-120, BY, 105, 28) then try_schedule() end
  else
    if clicked(WIN_W-120, BY, 105, 28) then do_cancel() end
  end

  last_cap = cap

  local char = gfx.getchar()
  if char == -1 then return end

  if char ~= 0 and active_id then
    local f = fmap[active_id]
    if f then
      if char == 8 then
        vals[f.id] = vals[f.id]:sub(1, -2)
      elseif char == 9 then
        active_id = fields[f.idx % #fields + 1].id
      elseif char == 27 then
        active_id = nil
      elseif char == 65362 then adjust_field(active_id, 1)
      elseif char == 65364 then adjust_field(active_id, -1)
      elseif char >= 48 and char <= 57 then
        if #vals[f.id] < f.ml then
          vals[f.id] = vals[f.id] .. string.char(char)
          if #vals[f.id] == f.ml and f.idx < #fields then
            active_id = fields[f.idx + 1].id
          end
        end
      end
    end
  end

  gfx.update()
  reaper.defer(loop)
end

-- Initialization
fill_dt(os.date("*t"))
vals.t_h = ""; vals.t_m = ""; vals.t_s = ""

loop()