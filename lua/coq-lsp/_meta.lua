---Position for indexing used by most API functions (0-based line, 0-based column) (:h api-indexing).
---@class APIPosition: { [1]: integer, [2]: integer }

---Position for "mark-like" indexing (1-based line, 0-based column) (:h api-indexing).
---@class MarkPosition: { [1]: integer, [2]: integer }

-- https://github.com/ejgallego/coq-lsp/blob/main/etc/doc/PROTOCOL.md

---@alias coqlsp.Pp string|any

---@class coqlsp.GoalRequest
---@field textDocument lsp.VersionedTextDocumentIdentifier
---@field position lsp.Position
---@field pp_format? 'Pp' | 'Str'
---@field pretac? string
---@field command? string
---@field mode? 'Prev' | 'After'

---@class coqlsp.Hyp
---@field names coqlsp.Pp[]
---@field def? coqlsp.Pp
---@field ty coqlsp.Pp

---@class coqlsp.Goal
---@field hyps coqlsp.Hyp[]
---@field ty coqlsp.Pp

---@class coqlsp.GoalConfig
---@field goals coqlsp.Goal[];
---@field stack {[1]: coqlsp.Goal[], [2]: coqlsp.Goal[]}[]
---@field bullet? coqlsp.Pp;
---@field shelf coqlsp.Goal[];
---@field given_up coqlsp.Goal[];

---@class coqlsp.Message
---@field range? lsp.Range
---@field level number
---@field text coqlsp.Pp

---@class coqlsp.GoalAnswer
---@field textDocument lsp.VersionedTextDocumentIdentifier
---@field position lsp.Position
---@field goals? coqlsp.GoalConfig
---@field messages coqlsp.Pp[] | coqlsp.Message[]
---@field error? coqlsp.Pp
---@field program? any

---@class coqlsp.CoqFileProgressProcessingInfo
---@field range lsp.Range
---@field kind? 1|2

---@class coqlsp.CoqFileProgressParams
---@field textDocument lsp.VersionedTextDocumentIdentifier
---@field processing coqlsp.CoqFileProgressProcessingInfo[]
