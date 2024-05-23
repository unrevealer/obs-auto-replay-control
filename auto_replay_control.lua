obs = obslua

--globals
local g = {
    --objects
    obj = {
        handler,
        props,
        current_scene,
        scene,
        scene_item,
        srcref,
        main_sig_handler,
    },
    --variables
    var = {
        srcname,
    }
}

function callback_hooked(src, title, class, exe) 
    obs.script_log(obs.LOG_INFO, "hooked")
    if not obs.obs_frontend_replay_buffer_active() then obs.obs_frontend_replay_buffer_start() end
end

function callback_unhooked(src) 
    obs.script_log(obs.LOG_INFO, "unhooked")
    if obs.obs_frontend_replay_buffer_active() then obs.obs_frontend_replay_buffer_stop() end
end

function init()
    --obs_source_t *obs_frontend_get_current_scene(void)
    g.obj.current_scene = obs.obs_frontend_get_current_scene()

    --obs_scene_t *obs_scene_from_source(const obs_source_t *source)
    g.obj.scene = obs.obs_scene_from_source(g.obj.current_scene)

    --obs_sceneitem_t *obs_scene_find_source_recursive(obs_scene_t *scene, const char *name)
    g.obj.scene_item = obs.obs_scene_find_source_recursive(g.obj.scene, g.var.srcname)

    --obs_source_t *obs_sceneitem_get_source(const obs_sceneitem_t *item)
    g.obj.srcref = obs.obs_sceneitem_get_source(g.obj.scene_item)
    if g.obj.srcref == nil then 
        obs.script_log(obs.LOG_INFO, "[ERR]: game cap source object not found")
        shutdown()
        return
    end
    obs.script_log(obs.LOG_INFO, "[LOG]: game cap source object found")

    --signal_handler_t *obs_source_get_signal_handler(const obs_source_t *source)
    --  void signal_handler_destroy(signal_handler_t *handler)
    g.obj.handler = obs.obs_source_get_signal_handler(g.obj.srcref)
    if g.obj.handler == nil then 
        obs.script_log(obs.LOG_INFO, "[ERR]: game cap signal handler not found")
        shutdown()
        return
    end
    
    --void signal_g.obj.handler_connect(signal_handler_t *handler, const char *signal, signal_callback_t callback)
    --  void signal_handler_disconnect(signal_handler_t *handler, const char *signal, signal_callback_t callback)
    obs.signal_handler_connect(g.obj.handler, "hooked", callback_hooked)
    obs.signal_handler_connect(g.obj.handler, "unhooked", callback_unhooked)

    --covers the case where the script is loaded while game cap is already active
    local cd = obs.calldata()
    obs.calldata_init(cd)
    local hook = obs.proc_handler_call(obs.obs_source_get_proc_handler(g.obj.srcref), "get_hooked", cd)
    if (obs.calldata_bool(cd, "hooked")) then
        obs.script_log(obs.LOG_INFO, "hooked on init")
        callback_hooked()
    end

    obs.script_log(obs.LOG_INFO, "init")
end

function shutdown()
    obs.signal_handler_disconnect(g.obj.main_sig_handler, "source_activate", main_sig_cb)

    if g.obj.handler ~= nil then
        obs.signal_handler_disconnect(g.obj.handler, "hooked", callback_hooked)
        obs.signal_handler_disconnect(g.obj.handler, "unhooked", callback_unhooked)
    
        --obs.signal_handler_destroy(g.obj.handler)
        g.obj.handler = nil
    end

    if g.obj.current_scene ~= nil then 
        obs.obs_source_release(g.obj.current_scene)

        g.obj.current_scene = nil
        g.obj.scene = nil
    end

    if g.obj.scene ~= nil then
        --obs.obs_scene_release(g.obj.scene)
        g.obj.current_scene = nil
        g.obj.scene = nil
    end

    if g.obj.scene_item ~= nil then 
        --obs.obs_sceneitem_release(g.obj.scene_item)
        g.obj.scene_item = nil
    end

    if g.obj.srcref ~= nil then 
        --obs.obs_source_release(g.obj.srcref)
        --g.obj.srcref = nil
    end

    obs.script_log(obs.LOG_INFO, "shutdown")
end

function script_description()
	return [[Starts OBS Replay when a Game Capture source produces output]]
end

function script_load(settings)
    g.var.srcname = obs.obs_data_get_string(settings, "srcname")

    obs.script_log(obs.LOG_INFO, "loaded")

    init()

    --signal_handler_t *obs_get_signal_handler(void)
    g.obj.main_sig_handler = obs.obs_get_signal_handler()
    obs.signal_handler_connect(g.obj.main_sig_handler, "source_activate", main_sig_cb)
end

function main_sig_cb(e)
    local name = obs.obs_source_get_name(obs.calldata_source(e, "source"))
    if name == g.var.srcname then
        obs.script_log(obs.LOG_INFO, "source_activate: "..name)

        shutdown()
        init()
    end
end

function script_unload()
    obs.script_log(obs.LOG_INFO, "script_unload")

    shutdown()
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "srcname", "Fullscreen GC")
end

function script_update(settings)
    obs.script_log(obs.LOG_INFO, "script_update")

    g.var.srcname = obs.obs_data_get_string(settings, "srcname")
end

function script_properties()
    g.obj.props = obs.obs_properties_create()

    obs.obs_properties_add_text(g.obj.props, "srcname", "Source Name", obs.OBS_TEXT_DEFAULT)

    obs.obs_properties_apply_settings(g.obj.props, settings)
	return g.obj.props
end


--[[ DUMPS OBS API FUNCTIONS
local function get_n_elements(tablee, n, start)
	local new_table = {}
	local start = start or 1
	for i=start, n do
		local element = tablee[i]
		if element ~= nil then
			table.insert(new_table, element)
		end
	end
	return new_table
end

function dump()
    local d = {name="obs", table=obslua}
    local global = d["table"]
    local name = d["name"]
    local part1 = {}
    local part2 = {}
    local amt = 0

    for i,v in pairs(global) do
        table.insert(part1, name .. "_" .. i)
        table.insert(part2, name .. "." .. i)
        amt = amt + 1
    end

    local message = "local " .. table.concat(part1, ", ") .. " = " .. table.concat(part2, ", ")
    local messages = {}

    local parts = 1
    if string.len(message) > 450 then
        parts = math.ceil(string.len(message) / 450)
    end

    local split_at = math.floor(#part1/parts)
    local start = 0

    for i=1, parts do
        local split_at_temp = split_at * i + 2
        local part1_1, part2_1 = get_n_elements(part1, split_at_temp, start+1), get_n_elements(part2, split_at_temp, start+1)
        table.insert(messages, "local " .. table.concat(part1_1, ", ") .. " = " .. table.concat(part2_1, ", "))
        start = split_at_temp
    end
    for i=1, #messages do
        obs.script_log(obs.LOG_INFO, messages[i])
    end
end
]]