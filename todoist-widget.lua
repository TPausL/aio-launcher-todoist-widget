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
local res = {}
local get_counter = 0

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

    http:get(base_uri .. "tasks?project_id=" .. project_id, "tasks")
end

function on_network_result_tasks(string, code)
    tasks = json.decode(string)

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

    for i, v in ipairs(tasks) do
        local tab = "&nbsp&nbsp&nbsp&nbsp"

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

        lines[i] = tab .. "● " .. "<span style=\"background-color: " .. background .. "\">" .. v["content"] .. "</span>" .. due
    end
    -- table.insert(lines, "<span style=\"background-color: #00FF00; width: 100%\" text-align=\"right \">test</font>")

    local title = ""

    if project_name == "" then
        title = "Project: " .. project_id
    else
        title = project_name
    end
    ui:show_lines({ "<b>" .. title .. "</b>", table.unpack(lines) })
end

function on_click(idx)
    if idx == 1 then
        http:get(base_uri .. "projects", "projects")
    else
        ui:show_toast("TODO: need to show editor")
    end
end

function on_network_result_projects(string, code)
    res = json.decode(string)

    projects = { "All Projects" }

    for i, v in ipairs(res) do
        projects[i + 1] = v["name"]
    end

    ui:show_radio_dialog("Select Project", projects)
end

function on_dialog_action(idx)
    if idx == -1 then
        return
    end
    if idx == 1 then
        project_id = ""
    else
        project_id = res[idx - 1]["id"]
    end
    project_name = projects[idx]


    files:write("project", project_id)
    files:write("project_name", projects[idx])

    main()
end
