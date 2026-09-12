local releases = require("releases")

function PLUGIN:Available(ctx)
    return releases.available()
end
