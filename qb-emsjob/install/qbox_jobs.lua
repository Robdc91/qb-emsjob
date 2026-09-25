--[[
    qb-emsjob | Qbox job setup (qbx_core)
    =====================================
    Qbox defines jobs in Lua (qbx_core/shared/jobs.lua), NOT in the database,
    so do NOT run install/ems_job.sql on a Qbox server.

    Out of the box: qbx_core already ships an 'ambulance' job (grades 0-4,
    Recruit/Paramedic/Doctor/Surgeon/Chief, type 'ems', defaultDuty true),
    and qb-emsjob checks grade LEVELS only (e.g. Config.MinGradeToRevive = 3),
    so the stock Qbox job works without any changes.

    Use this file only if you want the same ladder and salaries as the QBCore
    install (install/ems_job.sql). Copy the 'ambulance' block below into the
    table returned by qbx_core/shared/jobs.lua (replacing the stock entry),
    then restart qbx_core. Grade keys must be NUMBERS in Qbox.

    Assign the job in game afterwards:
      /setjob <player id> ambulance <0-3>

    Note on society money: on QBCore the invoice society credit goes through
    qb-management; on Qbox the same event call is pcall-guarded and becomes a
    no-op if your management resource does not bridge it. Configure invoice
    society deposits with your Qbox management resource of choice.
]]

-- qbx_core/shared/jobs.lua (excerpt - merge into the returned table):
--[[
['ambulance'] = {
    label = 'EMS',
    type = 'ems',
    defaultDuty = true,
    offDutyPay = false,
    grades = {
        [0] = { name = 'recruit',   payment = 50 },
        [1] = { name = 'paramedic', payment = 75 },
        [2] = { name = 'senior',    payment = 100 },
        [3] = { name = 'chief',     payment = 150, isboss = true, bankAuth = true },
    },
},
]]
