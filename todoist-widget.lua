-- type = "widget"
-- name = "Todoist"
-- description = "Integration with Todoist"
-- data_source = "https://todoist.com/app/"
-- author = "Timo Peters & Andrey Gavrilov"
-- version = "2.1
-- arguments_default = "0 0"

-- modules
local json = require "json"
local md_colors = require "md_colors"

-- constants
local decay_time = 6 * 60 * 60
local white = ui:get_colors().primary_text
local grey = ui:get_colors().secondary_text
local colors = {
    md_colors.red_500,
    md_colors.orange_500,
    md_colors.blue_500,
}

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

    api_set_token(token)
    api_get_projects()
end

function on_network_result_projects(res)
    files:write("todoist_projects", res)
    api_get_sections()
end

function on_network_result_sections(res)
    files:write("todoist_sections", res)
    api_get_tasks()
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

function select_project()
    local tab = {}
    table.insert(tab, "All projects")
    for i,v in ipairs(projects) do
        table.insert(tab, v.name)
    end

    dialog_id = "projects"
    ui:show_radio_dialog("Select project", tab, get_project_idx() + 1)
end

function on_dialog_projects(res)
    local args = settings:get()

    if res > 1 then
        args[2] = projects[res-1].id
    else
        args[2] = 0
    end

    settings:set(args)
    on_resume()
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

function on_settings()
    dialog_id = "settings"
    ui:show_edit_dialog("Enter your API token", "", settings:get()[1])
end

function on_dialog_settings(res)
    local args = settings:get()
    args[1] = res
    settings:set(args)
    on_alarm()
end

function redraw()
    local lines = {}
    local line = ""
    local project = tonumber(settings:get()[2])
    lines_id = {}

    if project == 0 then
        line = bold("All projects")
    else
        line = bold(get_project_name(project))
    end

    if os.time() - files:read("todoist_time") > decay_time then
        line = line.." (outdated)"
    end

    table.insert(lines, line)
    table.insert(lines_id, project)

    lines = insert_tasks(lines, project, 0)

    for i,v in ipairs(sections) do
        lines = insert_tasks(lines, project, v.id)
    end

    table.insert(lines, colored("Add task", grey))
    table.insert(lines_id, 0)

    ui:show_lines(lines)
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

            local line = task_text(v)..task_date(v)

            table.insert(tab, line)
            table.insert(lines_id, v.id)

            tab = insert_subtasks(tab, v.id, 1)
        end
    end
    return tab
end

function insert_subtasks(tab, id, lev)
    local curr_time = os.time()

    for i,v in ipairs(tasks) do
        if (v.parent_id == id) and not v.completed then
            local line = task_text(v)..task_date()

            for i = 1, lev do
                line = "&nbsp;&nbsp;&nbsp;"..line
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

            ui:show_rich_editor{
                text = v.content.."\n"..v.description,
                due_date = get_time(v.due),
                colors = colors,
                color = color,
                new = false
            }

            return
        end
    end
end

function on_dialog_task(res)
    if res == -1 then
        api_delete_task(task)
    else
        local body = create_task_json(res)
        api_edit_task(task, body)
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
            ui:show_context_menu{
                { "check", "Done" },
                { "trash", "Delete" }
            }
            return
        end
    end
    for i,v in ipairs(sections) do
        if v.id == id then
            dialog_id = "section"
            task = v.id
            ui:show_context_menu{
                { "trash", "Delete" }
            }
            return
        end
    end
    for i,v in ipairs(projects) do
        if (v.id == id) and (get_project_name(id) ~= "Inbox") then
            dialog_id = "project"
            task = v.id
            ui:show_context_menu{
                { "trash", "Delete" }
            }
            return
        end
    end

    ui:show_context_menu{
        { "repeat", "Refresh" }
    }
end

function on_context_menu_click(idx)
    if dialog_id == "task" then
        if idx == 1 then
            api_close_task(task)
        elseif idx == 2 then
            api_delete_task(task)
        end
    elseif dialog_id == "section" then
        api_delete_section(task)
    elseif dialog_id == "project" then
        api_delete_project(task)
    else
        on_alarm()
    end
end

function on_dialog_action(res)
    if res == -1 and dialog_id ~= "task" then
        return
    end

    if dialog_id == "settings" then
        on_dialog_settings(res)
    elseif dialog_id == "projects" then
        on_dialog_projects(res)
    elseif dialog_id == "task" then
        on_dialog_task(res)
    elseif dialog_id == "create" then
        on_dialog_create(res)
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

function create_task()
    dialog_id = "create"

    ui:show_rich_editor{
        due_date = 0,
        colors = colors,
        color = 6
    }
end

function on_dialog_create(res)
    local project = tonumber(settings:get()[2])
    local body = create_task_json(res, project)

    api_create_task(body)
end

function on_network_result_create(res, err)
    if err == 200 then
        ui:show_toast("Task created!")
        on_alarm()
        return
    end

    ui:show_toast("There was an error creating the task!")
end

function on_network_result_task(res, err)
    if err == 204 then
        ui:show_toast("Task updated!")
        on_alarm()
        return
    end

    ui:show_toast("There was an error updating the task!")
end

function on_network_error_create() show_no_connection() end
function on_network_error_task() show_no_connection() end
function on_network_error_close() show_no_connection() end
function on_network_error_delete() show_no_connection() end
function on_network_error_delete_sec() show_no_connection() end
function on_network_error_delete_pr() show_no_connection() end

function show_no_connection()
    ui:show_toast("No connection!")
end

-- Utils

function create_task_json(res, project)
    local priority = 1
    if res.color < 6 then
        priority = 5 - res.color
    end

    local body = {
        content = res.text,
        priority = priority,
        due_datetime = rfc822_date(res.due_date)
    }

    if project ~= nil and project > 0 then
        body.project_id = project
    end

    return json.encode(body)
end

-- Int date to RFC822 date
function rfc822_date(date)
    return os.date("%Y-%m-%dT%H:%M:00Z", date - system:get_tz_offset())
end

-- HTML-colored string
function colored(str, color)
    return "<font color=\""..color.."\">"..str.."</font>"
end

-- HTML bold string
function bold(str)
    return "<b>"..str.."</b>"
end

function task_text(v)
    local due_date = get_time(v.due)
    local dot = dot(due_date)
    local color = color_by_priority(v.priority)

    return "%%mkd%%"..colored(dot.." "..v.content, color)
end

function task_date(v)
    local due_date = get_time(v.due)

    if due_date == nil then
        return ""
    end

    local date = ""
    if os.date("%H:%M", due_date) == "00:00" then
        date = os.date("%d %b", due_date)
    else
        date = os.date("%d %b, %H:%M", due_date)
    end

    return colored(" - "..date, grey)
end

-- Dot in the beggining of task
function dot(due_date)
    local circle = "⬤ "

    if due_date ~= nil and due_date < os.time() then
        circle = "❗"
    end

    return circle
end

function color_by_priority(priority)
    local color = white

    if priority > 1 then
        color = colors[5 - priority]
    end

    return color
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
        due_date = os.time{
            year = due_date[1],
            month = due_date[2],
            day = due_date[3],
            hour = due_time[1],
            min = due_time[2],
            sec = 0
        } + offset
    end

    return due_date
end

-- Todoist API

local base_uri = "https://api.todoist.com/rest/v1/"

function api_set_token(token)
    http:set_headers{ "Authorization: Bearer "..token }
end

function api_get_projects()
    http:get(base_uri.."projects", "projects")
end

function api_get_sections()
    http:get(base_uri.."sections", "sections")
end

function api_get_tasks()
    http:get(base_uri.."tasks", "tasks")
end

function api_create_task(body)
    http:post(base_uri.."tasks/", body, "application/json", "create")
end

function api_delete_task(task_id)
    http:delete(base_uri.."tasks/"..task_id, "delete")
end

function api_edit_task(task_id, body)
    http:post(base_uri.."tasks/"..task_id, body, "application/json", "task")
end

function api_close_task(task_id)
    http:post(base_uri.."tasks/"..task_id.."/close", "", "application/json", "close")
end

function api_delete_section(task_id)
    http:delete(base_uri.."sections/"..task_id, "delete_sec")
end

function api_delete_project(task_id)
    http:delete(base_uri.."projects/"..task_id, "delete_pr")
end

