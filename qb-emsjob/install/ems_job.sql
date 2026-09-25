-- qb-emsjob | Job setup
-- Adds the 'ambulance' job and grades to qb-core management_jobs.
-- If the job already exists, re-run is safe thanks to ON DUPLICATE KEY.

INSERT INTO `management_jobs` (`name`, `label`, `account`, `whitelist`)
VALUES ('ambulance', 'EMS', 'ambulance', 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `is_boss`)
VALUES
    ('ambulance', 0, 'recruit',  'Recruited Paramedic', 500,  0),
    ('ambulance', 1, 'paramedic','Paramedic',           750,  0),
    ('ambulance', 2, 'senior',   'Senior Paramedic',    1000, 0),
    ('ambulance', 3, 'chief',    'EMS Chief',           1500, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `salary` = VALUES(`salary`), `is_boss` = VALUES(`is_boss`);

-- Assign a player to the job (replace the citizenid):
-- UPDATE `players` SET `job` = JSON_SET(`job`, '$.name', 'ambulance', '$.label', 'EMS', '$.grade', 3) WHERE `citizenid` = 'ABC123';
