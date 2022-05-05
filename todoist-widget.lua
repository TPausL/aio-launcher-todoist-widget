-- type = "widget"
-- name = "Todoist"
-- description = "Integration with Todoist"
-- data_source = "https://todoist.com/app/"
-- author = "Timo Peters"
-- version = "1.0
-- arguments_help = "Enter your API token"

json = require "json"

-- constants
local base_uri = "https://api.todoist.com/rest/v1/"

-- vars
local token = ""
local project = {}
local project_id = ""
local project_name = ""
local tasks = {}
local sections = {}
local project_names = {}
local api_projects = {}
local get_counter = 0
local selected_task = nil

function on_resume()

    token = settings:get()[1]

    if token == nil then
        ui:show_text("Please Enter your API token in the script settings!")
        return
    else
        setup()
    end

end

function setup()
    http:set_headers({ "Authorization: Bearer " .. token })

    project_id = files:read("project")
    project_name = files:read("project_name")

    if project_id == nil then
        http:get(base_uri .. "projects", "projects")
    else
        main()
    end
end

function main()
    if project_id == "all" then
        project_id = ""
    end

    http:get(base_uri .. "sections/?project_id=" .. project_id, "sections")
end

function on_network_result_sections(string, code)
    sections = {}
    local res = json.decode(string)
    for i,v in ipairs(res) do
        sections[v.id] = v
    end
    http:get(base_uri .. "tasks?project_id=" .. project_id, "tasks")
end

function on_network_result_tasks(string, code)
    tasks = json.decode(string)

    if #tasks == 0 then
        render_lines()
    end

    for i, v in ipairs(tasks) do
        get_counter = get_counter + 1
        http:get(base_uri .. "tasks/" .. v["id"], "task")
    end
end

function on_network_result_task(string, code)
    local r = json.decode(string)

    for i, v in ipairs(tasks) do
        if v["id"] == r["id"] then
            tasks[i] = r
        end
    end

    if #tasks == get_counter then
        get_counter = 0
        render_lines()
    end
end

function render_lines()
    local lines = {}

    if #tasks == 0 then
        lines[1] = "<font color=\"grey\"><i> - All done!</i></font>"
    end

    local section_lines = {}

    for id, v in pairs(sections) do
        section_lines[v["order"]] = {"%%mkd%%" ..  "### *" .. v["name"] .. "*" }
    end

    for i, v in ipairs(tasks) do
        local tab = "&nbsp;&nbsp;&nbsp;&nbsp;"

        if not v["parent_id"] then
            tab = ""
        end

        due = ""

        if v["due"] then
            due = "<font color=\"grey\"> - " .. v["due"]["string"] .. "</font>"
        end

        if v["priority"] == 1 then background = "transparent"
        elseif v["priority"] == 2 then background = "#246fe0"
        elseif v["priority"] == 3 then background = "#eb8909"
        elseif v["priority"] == 4 then background = "#d1453b" end

        --lines[i] = v["section_id"]
        local line =  tab .. "●" .. "<span style=\"background-color: " .. background .. "\">" .. v["content"] .. "</span>" .. due
        if v["section_id"] > 0 then
            table.insert(section_lines[sections[v["section_id"]]["order"]],"%%mkd%%" .. "&nbsp;&nbsp;" .. line)
        else 
            lines[i] = "%%mkd%%" .. line
        end 
    end

    for i, t in ipairs(section_lines) do
        for j, v in ipairs(t) do
            table.insert(lines, v)
        end
    end

    local title = ""

    if project_name == "" then
        title = "Project: " .. project_id
    else
        title = project_name
    end
    ui:show_lines({ "<b>" .. title .. "</b>", table.unpack(lines) })
end

function on_long_click(idx)
    if idx == 1 then return end
    selected_task = idx - 1
    ui:show_context_menu({ { "check", "Done" }, { "trash", "Delete" } })
end

function on_context_menu_click(idx)
    if idx == 1 then
        http:post(base_uri .. "tasks/" .. tasks[selected_task]["id"] .. "/close", "", "application/json", "task_done")
    end
    if idx == 2 then
        http:delete(base_uri .. "tasks/" .. tasks[selected_task]["id"], "task_done")

    end
end

function on_network_result_task_done(string, code)
    if code == 204 then
        http:get(base_uri .. "tasks?project_id=" .. project_id, "tasks")
        return
    end
    ui:show_toast("There was an error marking the task as done!")
end

function on_click(idx)
    if idx == 1 then
        http:get(base_uri .. "projects", "projects")
    else
        ui:show_toast("TODO: need to show editor")
    end
end

function on_network_result_projects(string, code)
    api_projects = json.decode(string)

    project_names = { "All Projects" }

    for i, v in ipairs(api_projects) do
        project_names[i + 1] = v["name"]
    end

    ui:show_radio_dialog("Select Project", project_names)
end

function on_dialog_action(idx)
    if idx == -1 then
        return
    end
    if idx == 1 then
        project_id = ""
    else
        project_id = api_projects[idx - 1]["id"]
    end
    project_name = project_names[idx]


    files:write("project", project_id)
    files:write("project_name", project_names[idx])

    main()
end
