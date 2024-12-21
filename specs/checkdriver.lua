local lester = require "lester"

local describe = lester.describe
local it       = lester.it
local expect   = lester.expect

CLUTTEALTEX_VERBOSITY = 0
local checkdriver = require "src_lua.texrunner.checkdriver".checkdriver

describe("Driver Detection and Validation", function()
    local mock_filemap = function(files)
        local result = {}
        for _, file in ipairs(files) do
            table.insert(result, { kind = "input", path = file })
        end
        return result
    end

    it("Detects dvips drivers correctly", function()
        local files = mock_filemap({
            "/path/to/graphics.sty",
            "/path/to/dvips.def",
        })
        local mismatches = checkdriver("dvips", files)
        expect.strict_eq(#mismatches, 0, "No mismatches should be detected for dvips")
    end)

    it("Detects pdftex drivers correctly", function()
        local files = mock_filemap({
            "/path/to/graphics.sty",
            "/path/to/pdftex.def",
        })
        local mismatches = checkdriver("pdftex", files)
        expect.strict_eq(#mismatches, 0, "No mismatches should be detected for pdftex")
    end)

    it("Detects xetex drivers correctly", function()
        local files = mock_filemap({
            "/path/to/graphics.sty",
            "/path/to/xetex.def",
        })
        local mismatches = checkdriver("xetex", files)
        expect.strict_eq(#mismatches, 0, "No mismatches should be detected for xetex")
    end)

    it("Reports mismatched drivers", function()
        local files = mock_filemap({
            "/path/to/graphics.sty",
            "/path/to/dvipdfmx.def",
        })
        local mismatches = checkdriver("dvips", files)
        expect.strict_eq(#mismatches, 1, "One mismatch should be detected")
        expect.equal(mismatches[1], "graphics", "Mismatch should be in graphics")
    end)

    it("Handles missing driver files gracefully", function()
        local files = mock_filemap({})
        local mismatches = checkdriver("pdftex", files)
        expect.strict_eq(#mismatches, 4, "All drivers should mismatch when no files are present")
    end)

    it("Handles expl3 detection with new backend correctly", function()
        local files = mock_filemap({
            "/path/to/expl3.sty",
            "/path/to/l3backend-pdfmode.def",
        })
        local mismatches = checkdriver("pdftex", files)
        expect.strict_eq(#mismatches, 0, "No mismatches should be detected for new expl3 backend")
    end)

    it("Handles expl3 detection with old backend correctly", function()
        local files = mock_filemap({
            "/path/to/expl3.sty",
            "/path/to/l3backend-xdvipdfmx.def",
        })
        local mismatches = checkdriver("xetex", files)
        expect.strict_eq(#mismatches, 0, "No mismatches should be detected for old expl3 backend")
    end)

    it("Detects hyperref drivers correctly", function()
        local files = mock_filemap({
            "/path/to/hyperref.sty",
            "/path/to/hpdftex.def",
        })
        local mismatches = checkdriver("pdftex", files)
        expect.strict_eq(#mismatches, 0, "No mismatches should be detected for hyperref")
    end)

    it("Detects xy-pic drivers correctly", function()
        local files = mock_filemap({
            "/path/to/xy.tex",
            "/path/to/xypdf.tex",
        })
        local mismatches = checkdriver("pdftex", files)
        expect.strict_eq(#mismatches, 0, "No mismatches should be detected for xy-pic")
    end)

    it("Reports mismatched xy-pic drivers", function()
        local files = mock_filemap({
            "/path/to/xy.tex",
            "/path/to/xypdf.tex",
        })
        local mismatches = checkdriver("dvips", files)
        expect.strict_eq(#mismatches, 1, "One mismatch should be detected")
        expect.strict_eq(mismatches[1], "xypic", "Mismatch should be in xy-pic")
    end)
end)
