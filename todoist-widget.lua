-- type = "widget"
-- name = "Todoist"
-- description = "Integration with Todoist"
-- data_source = "https://todoist.com/app/"
-- author = "Timo Peters & Andrey Gavrilov"
-- version = "2.0
-- arguments_default = "0 0"

-- modules
local json = require "json"
local md_colors = require "md_colors"

-- constants
local base_uri = "https://api.todoist.com/rest/v1/"
local colors = {md_colors.red_500, md_colors.orange_500, md_colors.blue_500}

-- vars
local projects = {}
local sections = {}
local tasks = {}
local dialog_id = ""
local lines_id = {}
local task = 0

function on_alarm()
	local args = settings:get()
	if not settings:get() then
		settings:set({0, 0})
	end
	local token = settings:get()[1]
	if tonumber(token) == 0 then
        ui:show_text("Tap to enter your API token!")
        return
	end
	http:set_headers({ "Authorization: Bearer " .. token })
	http:get(base_uri .. "projects", "projects")
end

function on_network_result_projects(res)
	files:write("todoist_projects", res)
	http:get(base_uri .. "sections", "sections")
end

function on_network_result_sections(res)
	files:write("todoist_sections", res)
	http:get(base_uri .. "tasks", "tasks")
end

function on_network_result_tasks(res, err)
	files:write("todoist_tasks", res)
	files:write("todoist_time", os.time())
	on_resume()
end

function on_resume()
	if not files:read("todoist_projects") then
		files:write("todoist_projects", json.encode({}))
	end
	if not files:read("todoist_sections") then
		files:write("todoist_sections", json.encode({}))
	end
	if not files:read("todoist_tasks") then
		files:write("todoist_tasks", json.encode({}))
	end
	projects = json.decode(files:read("todoist_projects"))
	sections = json.decode(files:read("todoist_sections"))
	tasks = json.decode(files:read("todoist_tasks"))
	redraw()
end

function on_click(idx)
	if tonumber(settings:get()[1]) == 0 then
		dialog_id = "settings"
		ui:show_edit_dialog("Enter your API token")
	elseif idx == 1 then
        select_project()
	elseif idx == #lines_id then
        create_task()
	else
		open_task(lines_id[idx])
	end
end

function on_settings()
	dialog_id = "settings"
	ui:show_edit_dialog("Enter your API token", "", settings:get()[1])
end

function on_dialog_action(res)
	if res == -1 and dialog_id ~= "task" then
		return
	end
	if dialog_id == "settings" then
		local args = settings:get()
		args[1] = res
		settings:set(args)
		on_alarm()
	elseif dialog_id == "projects" then
		local args = settings:get()
	    if res > 1 then
	        args[2] = projects[res-1].id
	    else
	        args[2] = 0
	    end
		settings:set(args)
		on_resume()
	elseif dialog_id == "task" then
	    if res == -1 then
	        http:delete(base_uri .. "tasks/" .. task, "delete")
	    else
	        local priority = 1
            if res.color < 6 then
                priority = 5 - res.color
            end
            local datetime = os.date("%Y-%m-%dT%H:%M:00Z", res.due_date - system:get_tz_offset())
            local body = {
                content = res.text,
                priority = priority,
                due_datetime = datetime
            }
            http:post(base_uri .. "tasks/" .. task, json.encode(body), "application/json", "task")
	    end
	elseif dialog_id == "create" then
        local priority = 1
        if res.color < 6 then
            priority = 5 - res.color
        end
        local datetime = os.date("%Y-%m-%dT%H:%M:00Z", os.time() - system:get_tz_offset())
        local body = {
            content = res.text,
            priority = priority,
            due_datetime = datetime
        }
        local project = tonumber(settings:get()[2])
        if project > 0 then
            body.project_id = project
        end
        http:post(base_uri .. "tasks/", json.encode(body), "application/json", "create")
    end
end

function redraw()
    local lines = {}
	lines_id = {}
    local project = tonumber(settings:get()[2])
	local line = "<b>"
    if project == 0 then
		line = line .. "All projects"
    else
		line = line .. get_project_name(project)
    end
	line = line .. "</b>"
	if os.time() - files:read("todoist_time") > 24 * 60 * 60 then
	    line = line .. " (Data is outdated)"
	end
	table.insert(lines, line)
	table.insert(lines_id, project)
	lines = insert_tasks(lines, project, 0)
    for i,v in ipairs(sections) do
		lines = insert_tasks(lines, project, v.id)
    end
    table.insert(lines, "<font color=\"" .. ui:get_colors().secondary_text .. "\">Add task</font>")
    table.insert(lines_id, 0)
    ui:show_lines(lines)
end

function select_project()
    local tab = {}
    table.insert(tab, "All projects")
    for i,v in ipairs(projects) do
        table.insert(tab, v.name)
    end
    dialog_id = "projects"
    ui:show_radio_dialog("Select project", tab, get_project_idx() + 1)
end

function get_project_idx()
    local project = tonumber(settings:get()[2])
    for i,v in ipairs(projects) do
        if project == v.id then
            return i
        end
    end
    return 0
end

function get_project_name()
    local project = tonumber(settings:get()[2])
    for i,v in ipairs(projects) do
        if project == v.id then
            return v.name
        end
    end
    return "All projects"
end

function get_section_name(id)
	for i,v in ipairs(sections) do
		if v.id == id then
			return v.name
		end
	end
end

function insert_tasks(tab, pr, sec)
	local is_sec = true
	for i,v in ipairs(tasks) do
		if ((pr == v.project_id) or (pr == 0)) and (sec == v.section_id) and (not v.parent) and not v.completed then
			if is_sec and sec ~= 0 then
				table.insert(tab, "<b><i>" .. get_section_name(sec) .. "</i></b>")
				table.insert(lines_id, sec)
				is_sec = false
			end
			local color = ui:get_colors().primary_text
			if v.priority > 1 then
			    color = colors[5 - v.priority]
			end
			local line = "%%mkd%%<font color=\"" .. color .. "\">&#8627; " .. v.content .. "</font>"
			local due_date = get_time(v.due)
			if due_date ~= nil then
			    line = line .. "<font color=\"" .. ui:get_colors().secondary_text .. "\"> - " .. os.date("%d %b, %H:%M", due_date) .. "</font>"
			    if due_date < os.time() then
			        line = line .. " (*)"
			    end
			end
			table.insert(tab, line)
			table.insert(lines_id, v.id)
			tab = insert_subtasks(tab, v.id, 1)
		end
	end
	return tab
end

function insert_subtasks(tab, id, lev)
	for i,v in ipairs(tasks) do
		if (v.parent_id == id) and not v.completed then
			local color = ui:get_colors().primary_text
			if v.priority > 1 then
			    color = colors[5 - v.priority]
			end
			local line = "<font color=\"" .. color .. "\">&#8627; " .. v.content .. "</font>"
			for i = 1, lev do
				line = "&nbsp;&nbsp;&nbsp;" .. line
			end
			line = "%%mkd%%" .. line
			local due_date = get_time(v.due)
			if due_date ~= nil then
			    line = line .. "<font color=\"" .. ui:get_colors().secondary_text .. "\"> - " .. os.date("%d %b, %H:%M", due_date) .. "</font>"
			    if due_date < os.time() then
			        line = line .. " (*)"
			    end
			end
			table.insert(tab, line)
			table.insert(lines_id, v.id)
			tab = insert_subtasks(tab, v.id, lev + 1)
		end
	end
	return tab
end

function open_task(id)
	for i,v in ipairs(tasks) do
		if v.id == id then
			dialog_id = "task"
			task = v.id
			local color = 6
			if v.priority > 1 then
			    color = 5 - v.priority
			end
            ui:show_rich_editor({
                text = v.content .. "\n" .. v.description,
                due_date = get_time(v.due),
                colors = colors,
                color = color,
                new = false
        })
			return
		end
	end
end

function on_long_click(idx)
	open_context_menu(lines_id[idx])
end

function open_context_menu(id)
	for i,v in ipairs(tasks) do
		if v.id == id then
			dialog_id = "task"
			task = v.id
			ui:show_context_menu({ { "check", "Done" }, { "trash", "Delete" } })
			return
		end
	end
	for i,v in ipairs(sections) do
		if v.id == id then
			dialog_id = "section"
			task = v.id
			ui:show_context_menu({ { "trash", "Delete" } })
			return
		end
	end
	for i,v in ipairs(projects) do
		if (v.id == id) and (get_project_name(id) ~= "Inbox") then
			dialog_id = "project"
			task = v.id
			ui:show_context_menu({ { "trash", "Delete" } })
			return
		end
	end
end

function on_context_menu_click(idx)
	if dialog_id == "task" then
		if idx == 1 then
			http:post(base_uri .. "tasks/" .. task .. "/close", "", "application/json", "close")
		elseif idx == 2 then
			http:delete(base_uri .. "tasks/" .. task, "delete")
		end
	elseif dialog_id == "section" then
		http:delete(base_uri .. "sections/" .. task, "delete_sec")
	elseif dialog_id == "project" then
		http:delete(base_uri .. "projects/" .. task, "delete_pr")
	end
end

function on_network_result_close(res, err)
    if err == 204 then
		ui:show_toast("Task closed!")
        on_alarm()
        return
    end
    ui:show_toast("There was an error closing the task!")
end

function on_network_result_delete(res, err)
    if err == 204 then
		ui:show_toast("Task deleted!")
        on_alarm()
        return
    end
    ui:show_toast("There was an error deleting the task!")
end

function on_network_result_delete_sec(res, err)
    if err == 204 then
		ui:show_toast("Section deleted!")
        on_alarm()
        return
    end
    ui:show_toast("There was an error deleting the section!")
end

function on_network_result_delete_pr(res, err)
    if err == 204 then
		ui:show_toast("Project deleted!")
		local args = settings:get()
		args[2] = 0
		settings:set(args)
        on_alarm()
        return
    end
    ui:show_toast("There was an error deleting the project!")
end

function on_network_error_close()
	show_no_connection()
end

function on_network_error_delete()
	show_no_connection()
end

function on_network_error_delete_sec()
	show_no_connection()
end

function on_network_error_delete_pr()
	show_no_connection()
end

function show_no_connection()
	ui:show_toast("No connection!")
end

function create_task()
    dialog_id = "create"
    ui:show_rich_editor({
        due_date = os.time(),
        colors = colors,
        color = 6
        })
end

function on_network_result_create(res, err)
    if err == 200 then
		ui:show_toast("Task created!")
        on_alarm()
        return
    end
    ui:show_toast("There was an error creating the task!")
end

function get_time(due)
	local due_date = nil
	local due_time = nil
	local offset = 0
	if due ~= nil then
		if due.datetime ~= nil then
		    due_time = due.datetime:split("T")
			due_time = due_time[2]:split(":")
			offset = system:get_tz_offset()
		else
			due_time = {0, 0}
		end
		due_date = due.date:split("-")
	end
	if due_date ~= nil then
		due_date = os.time{year = due_date[1], month = due_date[2], day = due_date[3], hour = due_time[1], min = due_time[2], sec = 0} + offset
	end
	return due_date
end

function on_network_result_task(res, err)
    if err == 204 then
		ui:show_toast("Task updated!")
        on_alarm()
        return
    end
    ui:show_toast("There was an error updating the task!")
end

function on_network_error_create()
	show_no_connection()
end

function on_network_error_task()
	show_no_connection()
end
