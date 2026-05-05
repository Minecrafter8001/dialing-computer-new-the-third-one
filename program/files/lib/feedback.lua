-- Feedback code handling and translation

local util = require("lib.util")

local FEEDBACK_FILE = "feedback_codes.json"
local FEEDBACK_OK = 0

local function loadFeedbackMessages()
    local decoded, errorMessage = util.loadJSONFile(FEEDBACK_FILE)
    if errorMessage ~= nil then
        return nil, errorMessage
    end

    return decoded, nil
end

local function getFeedbackMessage(feedbackMessages, feedback)
    if type(feedback) ~= "number" then
        return tostring(feedback)
    end

    local feedbackInfo = feedbackMessages[tostring(feedback)]
    if type(feedbackInfo) == "table" then
        local label = feedbackInfo.label or feedbackInfo.name
        if type(label) == "string" and label ~= "" then
            return label
        end
    elseif type(feedbackInfo) == "string" and feedbackInfo ~= "" then
        return feedbackInfo
    end

    return "unknown feedback"
end

local function formatFeedback(feedbackMessages, feedback)
    return tostring(feedback) .. " (" .. getFeedbackMessage(feedbackMessages, feedback) .. ")"
end

return {
    FEEDBACK_FILE = FEEDBACK_FILE,
    FEEDBACK_OK = FEEDBACK_OK,
    loadFeedbackMessages = loadFeedbackMessages,
    getFeedbackMessage = getFeedbackMessage,
    formatFeedback = formatFeedback,
}
