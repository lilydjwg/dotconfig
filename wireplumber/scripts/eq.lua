lutils = require ("linking-utils")
cutils = require ("common-utils")
log = Log.open_topic ("s-linking")

use_which_eq = function(name, device_id)
  log:debug("use_which_eq: " .. name .. ", " .. tostring(device_id))
  if name == "alsa_output.pci-0000_0f_00.4.analog-stereo" then
    return 'bose'
  elseif name == "bluez_output.C8_7B_23_7F_7F_81.1" then
    return 'bose'
  elseif name == "bluez_output.0C_AE_BD_26_A6_63.1" then
    return 'edifier'
  elseif name:match("alsa_output%.pci%-0000_00_1f%.3.*%.analog%-stereo") then
    local port_name = get_device_port_name(device_id)
    log:debug("port_name: " .. tostring(port_name))
    if port_name == "analog-output-headphones" then
      return 'bose'
    end
  end
end

find_eq = function(om, name)
  local target = om:lookup {
    type = "SiLinkable",
    Constraint { "node.name", "=", "effect_input." .. name .. "_eq" },
  }
  return target
end

find_eq_target = function(om, eq_name)
  for target in om:iterate {
    type = "SiLinkable",
    Constraint { "item.node.type", "=", "device" },
    Constraint { "item.node.direction", "=", "input" },
    Constraint { "media.class", "=", "Audio/Sink" },
  } do
    local target_props = target.properties
    local target_name = target_props["node.name"]
    if use_which_eq(target_name) == eq_name then
      return target
    end
  end
end

get_device_port_name = function(device_id)
  if device_id then
    local device = cutils.get_object_manager("device"):lookup {
      type = "device",
      Constraint { "object.id", "=", device_id },
    }
    if device then
      for p in device:iterate_params("Route") do
        local route = cutils.parseParam(p, "Route")
        if route.direction == "Output" then
          return route.name
        end
      end
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
    -- not sure why but occasionally it is nil
    if not target then return end
    local name = si_props["node.name"]
    local target_direction = cutils.getTargetDirection(si_props)
    local target_props = target.properties
    local target_name = target_props["node.name"]
    local dont_move = cutils.parseBool(si_props["node.dont-move"])
    local device_id = target_props["device.id"]

    log:info("name: " .. name .. " target: " .. target_props["node.name"])

    if not dont_move
      and not si_flags.has_defined_target
      and target_direction == "input"
      and not name:match("effect_output%..*_eq") then
      local eq_name = use_which_eq(target_name, device_id)
      if eq_name then
        log:info("switched name: " .. name)
        event:set_data("target", find_eq(om, eq_name))
      end
    end

    local eq_name = name:match("effect_output%.(.*)_eq")
    if eq_name and not use_which_eq(target_name, device_id) then
      local t = find_eq_target(om, eq_name)
      log:info("found eq target: " .. tostring(t))
      if t then
        event:set_data("target", t)
      end
    end
  end
}:register ()
