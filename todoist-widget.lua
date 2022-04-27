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
    ui:show_text(project_id)
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
