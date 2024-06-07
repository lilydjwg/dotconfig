lutils = require ("linking-utils")
cutils = require ("common-utils")
log = Log.open_topic ("s-linking")

should_use_bose_eq = function(name)
  if name == "alsa_output.pci-0000_0f_00.4.analog-stereo" then
    return true
  elseif name == "bluez_output.C8_7B_23_7F_7F_81.1" then
    return true
  end
end

find_bose_eq = function(om)
  local target = om:lookup {
    type = "SiLinkable",
    Constraint { "node.name", "=", "effect_input.bose_eq" },
  }
  return target
end

find_bose = function(om)
  for target in om:iterate {
    type = "SiLinkable",
    Constraint { "item.node.type", "=", "device" },
    Constraint { "item.node.direction", "=", "input" },
    Constraint { "media.class", "=", "Audio/Sink" },
  } do
    local target_props = target.properties
    local target_name = target_props["node.name"]
    if should_use_bose_eq(target_name) then
      return target
    end
  end
end

SimpleEventHook {
  name = "linking/bose-eq",
  after = "linking/find-best-target",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function (event)
    local source, om, si, si_props, si_flags, target = lutils:unwrap_select_target_event (event)
    local name = si_props["node.name"]
    local target_direction = cutils.getTargetDirection(si_props)
    local target_props = target.properties
    local target_name = target_props["node.name"]
    local dont_move = cutils.parseBool(si_props["node.dont-move"])

    log:info("name: " .. name .. " target: " .. target_props["node.name"])

    if not dont_move
      and not si_flags.has_defined_target
      and target_direction == "input"
      and name ~= "effect_output.bose_eq" then
      if should_use_bose_eq(target_name) then
        log:info("switched name: " .. name)
        event:set_data("target", find_bose_eq(om))
      end
    end

    if name == "effect_output.bose_eq" and not should_use_bose_eq(target_name) then
      local t = find_bose(om)
      log:info("found bose: " .. tostring(t))
      if t then
        event:set_data("target", t)
      end
    end
  end
}:register ()
