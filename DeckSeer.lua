--- STEAMODDED HEADER
--- MOD_NAME: Deck Preview
--- MOD_ID: deckpreview
--- MOD_AUTHOR: [LiMetal_real]
--- MOD_DESCRIPTION: Movable overlay that previews the next X cards you will draw.

-------------------------------------------------
-- ONE FILE, ONE TRUTH – do not duplicate blocks!
-------------------------------------------------

-----------------------------
-- SETTINGS & GLOBAL STATE --
-----------------------------
if not DeckPreview then DeckPreview = { TAG = "DeckPreview" } end

if not G.SETTINGS.DeckPreview then
  G.SETTINGS.DeckPreview = {
    preview_count   = 10,
    position_locked = true,
    position        = nil,
    anchor          = "Top Right"
  }
end

DeckPreview.settings        = G.SETTINGS.DeckPreview
DeckPreview.ready           = false      -- Preview erst nach erstem echten Draw
DeckPreview.dir             = nil        -- 'head' oder 'tail'
DeckPreview.top_off         = 0          -- Karten, die vom Top bereits gezogen sind (Offset)
DeckPreview.init_deck_size  = nil        -- Deckgröße vor dem ersten Draw
DeckPreview._last_sig       = nil        -- Dedup-Signatur für Draw-Events
DeckPreview.DEBUG           = true
DeckPreview._hooked         = false

local function get_setting(k) return DeckPreview.settings[k] end
local function set_setting(k,v) DeckPreview.settings[k] = v; G:save_settings() end

-----------------
--  DEBUG UTIL --
-----------------
local orig_sendDebugMessage = sendDebugMessage or print
local function dbg(s) if DeckPreview.DEBUG then orig_sendDebugMessage(s, DeckPreview.TAG) end end
local function card_str(c) return (c and c.base) and ((c.base.value or '?')..' of '..(c.base.suit or '?')) or 'nil' end

---------------------------
--  UI UPDATE FUNCTION   --
---------------------------
local function update_DeckPreview_display()
  if not DeckPreview.ready or not DeckPreview.container or not G.deck then return end

  local want = get_setting('preview_count') or 10
  local deck = G.deck.cards or {}
  local skip = 0  -- deck already excludes drawn cards, no offset needed

  DeckPreview.container:remove_all_cards()

  if not DeckPreview.dir then
    DeckPreview.dir = 'head'
    dbg('DIR defaulted to head')
  end

  local added = 0
  if DeckPreview.dir == 'tail' then
    local start = #deck
    for i = start, 1, -1 do
      local c = deck[i]
      if c and c.base then
        DeckPreview.container:add_card_text(card_str(c))
        added = added + 1
        if added >= want then break end
      end
    end
  else
    for i = 1, #deck do
      local c = deck[i]
      if c and c.base then
        DeckPreview.container:add_card_text(card_str(c))
        added = added + 1
        if added >= want then break end
      end
    end
  end

  DeckPreview.container:recalculate()
  dbg(string.format('Preview added=%d want=%d dir=%s deck=%d', added, want, DeckPreview.dir or 'nil', #deck))
end

----------------------
--  UI CONTAINER    --
----------------------
DeckPreviewContainer = MoveableContainer:extend()

function DeckPreviewContainer:init(args)
  args.header = { n = G.UIT.T, config = { text = 'Deck Preview', scale = 0.3, colour = G.C.WHITE } }
  args.nodes  = {
    { n = G.UIT.R, config = { minh = 0.1 }, nodes = {} },
    { n = G.UIT.R, config = { id = 'card_list', minh = 2.5 }, nodes = {} }
  }
  args.config = args.config or {}
  args.config.locked = get_setting('position_locked')
  args.config.anchor = get_setting('anchor')
  args.config.minh   = 2.8
  args.config.minw   = 2.0
  MoveableContainer.init(self, args)
end

function DeckPreviewContainer:drag(offset)
  MoveableContainer.drag(self, offset)
  local x,y = self:get_relative_pos()
  set_setting('position', {x=x,y=y})
end

function DeckPreviewContainer:add_card_text(txt)
  local list = self:get_UIE_by_ID('card_list')

  -- Rank/Suit trennen: "<Rank> of <Suit>"
  local rank, suit = txt:match("^(.-)%s+of%s+(%a+)")

  -- Farbwahl nach Suit
  local colour = G.C.WHITE
  if suit == 'Hearts' then
    colour = G.C.RED
  elseif suit == 'Spades' then
    colour = (G.C.BLACK or G.C.UI.TEXT_DARK or G.C.WHITE)
  elseif suit == 'Clubs' then
    colour = G.C.BLUE
  elseif suit == 'Diamonds' then
    colour = (G.C.GOLD or {1,0.65,0})
  end

  local nodes
  if rank and suit then
    nodes = {
      { n = G.UIT.T, config = { text = rank .. ' of ', scale = 0.3, colour = G.C.WHITE } },
      { n = G.UIT.T, config = { text = suit,        scale = 0.3, colour = colour       } },
    }
  else
    -- Fallback: ganze Zeile einfärben
    nodes = {
      { n = G.UIT.T, config = { text = txt, scale = 0.3, colour = colour } }
    }
  end

  self:add_child({ n = G.UIT.R, nodes = nodes }, list)
end

function DeckPreviewContainer:remove_all_cards()
  local list = self:get_UIE_by_ID('card_list')
  remove_all(list.children)
end

function DeckPreviewContainer:bl_toggle_lock()
  MoveableContainer.bl_toggle_lock(self)
  set_setting('position_locked', not self.states.drag.can)
end

function DeckPreviewContainer:bl_cycle_anchor_point()
  MoveableContainer.bl_cycle_anchor_point(self)
  set_setting('anchor', self.states.anchor)
  local x,y = self:get_relative_pos()
  set_setting('position', {x=x,y=y})
end

local function get_default_pos()
  return { x = G.consumeables.T.x + G.consumeables.T.w, y = G.consumeables.T.y + G.consumeables.T.h + 0.4 }
end

-----------------
--  HOOK SETUP --
-----------------
local function DeckPreview_init()
  if DeckPreview._hooked then return end
  DeckPreview._hooked = true

  local orig_game_start_run         = Game.start_run
  local orig_draw_from_deck_to_hand = G.FUNCS.draw_from_deck_to_hand

  function Game:start_run(args)
    orig_game_start_run(self, args)

    local pos = get_setting('position') or get_default_pos()
    local container = DeckPreviewContainer{ T = {pos.x, pos.y, 0, 0}, config = { align='tr', offset={x=0,y=0}, major=self } }
    DeckPreview.container = container
    DeckPreview.container.states.visible = false

    DeckPreview.ready          = false
    DeckPreview.dir            = nil
    DeckPreview.top_off        = 0
    DeckPreview.init_deck_size = nil
    DeckPreview._last_sig      = nil

    dbg('START_RUN: deck='..(#(G.deck and G.deck.cards or {}))..' wait for first draw...')
  end

  function G.FUNCS.draw_from_deck_to_hand(e)
    local deck_pre  = (G.deck and G.deck.cards) and #G.deck.cards or 0
    local d_cards   = (G.deck and G.deck.cards) or {}
    local cand_tail = d_cards[#d_cards]
    local cand_head = d_cards[1]

    dbg(string.format('DRAW pre: deck=%d', deck_pre))
    local top_pred = (DeckPreview.dir=='tail') and d_cards[#d_cards] or d_cards[1]
    if top_pred then dbg('PREDICT next='..card_str(top_pred)) end

    orig_draw_from_deck_to_hand(e)

    G.E_MANAGER:add_event(Event({
      trigger   = 'condition',
      ref_table = _G,
      condition = function() return G.STATE ~= G.STATES.DRAW_TO_HAND end,
      func = function()
        local deck_post = (G.deck and G.deck.cards) and #G.deck.cards or deck_pre
        local drawn     = math.max(deck_pre - deck_post, 0)

        -- Dedup anhand Deckgrößen-Übergang
        local sig = deck_pre..'>'..deck_post
        if DeckPreview._last_sig == sig then
          dbg('SKIP duplicate draw event '..sig)
          return true
        end
        DeckPreview._last_sig = sig

        if not DeckPreview.ready and drawn > 0 then
          DeckPreview.ready = true
          if DeckPreview.container then DeckPreview.container.states.visible = true end
        end

        -- Initiale Deckgröße einmalig bestimmen
        if not DeckPreview.init_deck_size and drawn > 0 then
          -- Größe vor diesem Draw = deck_post + drawn
          DeckPreview.init_deck_size = deck_post + drawn
        end

        -- Richtung einmalig bestimmen
        if not DeckPreview.dir and drawn > 0 then
          local hand_sz = (G.hand and #G.hand.cards) or 0
          local newest = {}
          for i = hand_sz - drawn + 1, hand_sz do newest[#newest+1] = G.hand.cards[i] end
          local found_tail, found_head = false, false
          for _,c in ipairs(newest) do
            if c == cand_tail then found_tail = true end
            if c == cand_head then found_head = true end
          end
          DeckPreview.dir = (found_tail and not found_head) and 'tail' or 'head'
          dbg('DETECT dir='..DeckPreview.dir..' (tail='..tostring(found_tail)..', head='..tostring(found_head)..')')
        end

        -- Offset **nicht addieren**, sondern aus Differenz berechnen
        if DeckPreview.init_deck_size then
          DeckPreview.top_off = 0  -- no offset; we always peek from current deck top
        end

        dbg(string.format('DRAW post: drawn=%d dir=%s deck=%d', drawn, DeckPreview.dir or 'nil', deck_post))
        update_DeckPreview_display()
        return true
      end
    }))
  end

  local orig_update = Game.update
  function Game:update(dt)
    orig_update(self, dt)
    if DeckPreview.container then
      local visible = (
        self.STATE == self.STATES.SELECTING_HAND or
        self.STATE == self.STATES.HAND_PLAYED   or
        self.STATE == self.STATES.DRAW_TO_HAND
      ) and get_setting('preview_count') > 0
      DeckPreview.container.states.visible = visible and DeckPreview.ready
    end
  end
end

----------------
-- BOOTSTRAP --
----------------
if Game and Game.start_run then
  DeckPreview_init()
else
  G.E_MANAGER:add_event(Event({
    trigger='condition', ref_table=_G,
    condition=function() return Game and Game.start_run end,
    func=function() DeckPreview_init(); return true end
  }))
end

--------------
--  THE END --
--------------
