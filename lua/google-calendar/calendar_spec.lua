---@diagnostic disable: undefined-field
local calendar = require('google-calendar.calendar')

local function offset_suffix()
  local offset = tostring(os.date('%z'))
  return offset:sub(1, 3) .. ':' .. offset:sub(4, 5)
end

local function dates(grid)
  local result = {}
  for _, week in ipairs(grid.weeks) do
    for _, cell in ipairs(week) do
      table.insert(result, cell.date)
    end
  end
  return result
end

describe('calendar', function()
  describe('parse_month', function()
    it('YYYY-MM を年と月に分解する', function()
      local year, month = calendar.parse_month('2026-11')

      assert.are.equal(2026, year)
      assert.are.equal(11, month)
    end)

    it('存在しない月は nil を返す', function()
      assert.is_nil(calendar.parse_month('2026-13'))
      assert.is_nil(calendar.parse_month('2026-00'))
    end)

    it('YYYY-MM 以外の形式は nil を返す', function()
      assert.is_nil(calendar.parse_month('2026-1'))
      assert.is_nil(calendar.parse_month('abc'))
      assert.is_nil(calendar.parse_month('2026/11'))
    end)
  end)

  describe('days_in_month', function()
    it('月ごとの日数を返す', function()
      assert.are.equal(31, calendar.days_in_month(2026, 1))
      assert.are.equal(28, calendar.days_in_month(2026, 2))
      assert.are.equal(31, calendar.days_in_month(2026, 3))
      assert.are.equal(30, calendar.days_in_month(2026, 4))
      assert.are.equal(31, calendar.days_in_month(2026, 12))
    end)

    it('閏年の 2 月は 29 日を返す', function()
      assert.are.equal(29, calendar.days_in_month(2024, 2))
      assert.are.equal(29, calendar.days_in_month(2000, 2))
      assert.are.equal(28, calendar.days_in_month(1900, 2))
    end)
  end)

  describe('month_grid', function()
    it('常に 6 週×7 日の 42 セルを返す', function()
      local grid = calendar.month_grid(2026, 10, 'sunday')

      assert.are.equal(6, #grid.weeks)
      for _, week in ipairs(grid.weeks) do
        assert.are.equal(7, #week)
      end
      assert.are.equal(42, #dates(grid))
    end)

    it('月初が日曜以外のときは前月の日で第 1 週を埋める', function()
      local grid = calendar.month_grid(2026, 10, 'sunday')

      assert.are.same({
        { date = '2026-09-27', day = 27, in_month = false, weekday = 0 },
        { date = '2026-09-28', day = 28, in_month = false, weekday = 1 },
        { date = '2026-09-29', day = 29, in_month = false, weekday = 2 },
        { date = '2026-09-30', day = 30, in_month = false, weekday = 3 },
        { date = '2026-10-01', day = 1, in_month = true, weekday = 4 },
        { date = '2026-10-02', day = 2, in_month = true, weekday = 5 },
        { date = '2026-10-03', day = 3, in_month = true, weekday = 6 },
      }, grid.weeks[1])
      assert.are.equal('2026-09-27', dates(grid)[1])
      assert.are.equal('2026-11-07', dates(grid)[42])
    end)

    it('月初が日曜のときは第 1 週が月初から始まる', function()
      local grid = calendar.month_grid(2026, 11, 'sunday')

      assert.are.equal('2026-11-01', dates(grid)[1])
      assert.is_true(grid.weeks[1][1].in_month)
      assert.are.equal(1, grid.weeks[1][1].day)
    end)

    it('月初が月曜のときは週の開始設定に従って前月の日を埋める', function()
      local sunday_grid = calendar.month_grid(2026, 6, 'sunday')
      local monday_grid = calendar.month_grid(2026, 6, 'monday')

      assert.are.equal('2026-05-31', dates(sunday_grid)[1])
      assert.are.equal(0, sunday_grid.weeks[1][1].weekday)
      assert.are.equal('2026-06-01', dates(monday_grid)[1])
      assert.are.equal(1, monday_grid.weeks[1][1].weekday)
      assert.is_true(monday_grid.weeks[1][1].in_month)
    end)

    it('閏年の 2 月も同じ計算で 42 セルを返す', function()
      local grid = calendar.month_grid(2024, 2, 'sunday')
      local all = dates(grid)

      assert.are.equal(42, #all)
      assert.is_true(vim.tbl_contains(all, '2024-02-29'))
      assert.are.equal('2024-02-29', all[33])
      assert.are.equal('2024-03-09', all[42])
    end)

    it('2 月と 30 日の月も同じ計算で 42 セルを返す', function()
      local february = dates(calendar.month_grid(2026, 2, 'sunday'))
      local april = dates(calendar.month_grid(2026, 4, 'sunday'))

      assert.are.equal(42, #february)
      assert.are.equal('2026-02-28', february[28])
      assert.are.equal(42, #april)
      assert.are.equal('2026-04-30', april[33])
    end)
  end)

  describe('add_days', function()
    it('日付を前後に加算し、月と年をまたぐ', function()
      assert.are.equal('2026-10-28', calendar.add_days('2026-10-27', 1))
      assert.are.equal('2026-10-26', calendar.add_days('2026-10-27', -1))
      assert.are.equal('2026-11-03', calendar.add_days('2026-10-27', 7))
      assert.are.equal('2027-01-01', calendar.add_days('2026-12-31', 1))
      assert.are.equal('2026-02-28', calendar.add_days('2026-03-01', -1))
      assert.are.equal('2024-02-29', calendar.add_days('2024-02-28', 1))
    end)
  end)

  describe('add_months', function()
    it('月を前後に加算し、年をまたぐ', function()
      local year, month = calendar.add_months(2026, 10, 1)
      assert.are.equal(2026, year)
      assert.are.equal(11, month)

      year, month = calendar.add_months(2026, 12, 1)
      assert.are.equal(2027, year)
      assert.are.equal(1, month)

      year, month = calendar.add_months(2026, 1, -1)
      assert.are.equal(2025, year)
      assert.are.equal(12, month)

      year, month = calendar.add_months(2026, 10, 3)
      assert.are.equal(2027, year)
      assert.are.equal(1, month)
    end)
  end)

  describe('clamp_day', function()
    it('月末を超える日を月末に丸める', function()
      assert.are.equal(28, calendar.clamp_day(2026, 2, 31))
      assert.are.equal(29, calendar.clamp_day(2024, 2, 31))
      assert.are.equal(30, calendar.clamp_day(2026, 11, 31))
      assert.are.equal(15, calendar.clamp_day(2026, 11, 15))
    end)
  end)

  describe('format_month_title', function()
    it('日本語の月タイトルを返す', function()
      assert.are.equal('2026年10月', calendar.format_month_title(2026, 10))
      assert.are.equal('2026年1月', calendar.format_month_title(2026, 1))
    end)
  end)

  describe('weekday_labels', function()
    it('週の開始曜日に合わせた曜日ヘッダーを返す', function()
      assert.are.same({ '日', '月', '火', '水', '木', '金', '土' }, calendar.weekday_labels('sunday'))
      assert.are.same({ '月', '火', '水', '木', '金', '土', '日' }, calendar.weekday_labels('monday'))
    end)
  end)

  describe('rfc3339', function()
    it('ローカルオフセット付きの RFC3339 を返す', function()
      assert.are.equal('2026-11-01T00:00:00' .. offset_suffix(), calendar.rfc3339('2026-11-01'))
      assert.are.equal('2026-11-01T09:30:00' .. offset_suffix(), calendar.rfc3339('2026-11-01', '09:30:00'))
    end)
  end)

  describe('fetch_range', function()
    it('月初を含む週の開始から 42 日分の取得範囲を返す', function()
      local start_date, end_date, time_min, time_max = calendar.fetch_range(2026, 10, 'sunday')

      assert.are.equal('2026-09-27', start_date)
      assert.are.equal('2026-11-08', end_date)
      assert.are.equal('2026-09-27T00:00:00' .. offset_suffix(), time_min)
      assert.are.equal('2026-11-08T00:00:00' .. offset_suffix(), time_max)
    end)
  end)

  describe('today', function()
    it('今日を YYYY-MM-DD 形式で返す', function()
      assert.are.equal(os.date('%Y-%m-%d'), calendar.today())
    end)
  end)
end)
