-- qb-emsjob | Billing setup
-- 1) Insurance table (optional; enable via Config.Insurance.enabled)
-- 2) qb-phone invoice table (created by qb-phone itself; statement kept for reference)

CREATE TABLE IF NOT EXISTS `player_insurance` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    `expires` DATE NULL DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `citizenid` (`citizenid`)
);

-- qb-phone creates phone_invoices on its own ensure; for manual installs the
-- expected shape is:
-- CREATE TABLE IF NOT EXISTS `phone_invoices` (
--     `id` INT NOT NULL AUTO_INCREMENT,
--     `citizenid` VARCHAR(50) NOT NULL,
--     `amount` INT NOT NULL,
--     `society` VARCHAR(50) DEFAULT NULL,
--     `sender` VARCHAR(50) DEFAULT NULL,
--     `reason` VARCHAR(255) DEFAULT NULL,
--     `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
--     PRIMARY KEY (`id`)
-- );

-- Give a player insurance for 90 days:
-- INSERT INTO player_insurance (citizenid, active, expires)
-- VALUES ('ABC123', 1, DATE_ADD(CURDATE(), INTERVAL 90 DAY))
-- ON DUPLICATE KEY UPDATE active = 1, expires = VALUES(expires);
