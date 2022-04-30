-- type = "widget"
-- name = "Todoist"
-- description = "Integration with Todoist"
-- data_source = "https://todoist.com/app/"
-- author = "Timo Peters"
-- version = "1.0
-- arguments_help = "Enter your API token"

json = require "json"

base_uri = "https://api.todoist.com/rest/v1/"


function main()
    -- ui:show_text(project_id)
    if project_id == "all" then
        project_id = ""
    end
    http:get(base_uri .. "tasks?project_id=" .. project_id, "tasks")
end

function on_network_result_tasks(string, code)
    tasks = json.decode(string)
    for i, v in ipairs(tasks) do
        http:get(base_uri .. "tasks/" .. v["id"], "task")
    end
end

function render_lines()
    lines = {}
    for i, v in ipairs(tasks) do
        tab = "&nbsp&nbsp&nbsp&nbsp"
        if not v["parent_id"] then
            tab = ""
        end
        due = ""
        if v["due"] then
            due = "<font color=\"grey\"> - " .. v["due"]["string"] .. "</font>"
        end
        if v["priority"] == 1 then
            background = "transparent"
        elseif v["priority"] == 2 then background = "#246fe0"
        elseif v["priority"] == 3 then background = "#eb8909"
        elseif v["priority"] == 4 then background = "#d1453b" end
        lines[i] = tab .. "● " .. "<span style=\"background-color: " .. background .. "\">" .. v["content"] .. "</span>" .. due
    end
    -- table.insert(lines, "<span style=\"background-color: #00FF00; width: 100%\" text-align=\"right \">test</font>")
    ui:show_lines(lines)

end

function on_network_result_task(string, code)
    local r = json.decode(string)
    for i, v in ipairs(tasks) do
        if v["id"] == r["id"] then
            tasks[i] = r
        end
    end
    render_lines()

end

function setup()
    project_id = files:read("project")
    if project_id == nil then
        http:get(base_uri .. "projects", "setup")
    else
        main()
    end
end

function on_network_result_setup(string, code)
    res = json.decode(string)
    names = { "All Projects" }
    for i, v in ipairs(res) do
        names[i + 1] = v["name"]
    end
    ui:show_buttons({ "Select Project" })
end

function on_click()
    ui:show_radio_dialog("Select Project", names)
end

function on_dialog_action(project)
    if project == -1 then
        return
    end
    project_id = res[project - 1]["id"]
    files:write("project", project_id)
    main()
end

function on_resume()
    local token = settings:get()[1]
    if token == nil then
        ui:show_text("Please Enter your API token in the script settings!")
        return
    end
    http:set_headers({ "Authorization: Bearer " .. token })


    setup()


end
