-- sql.sql
CREATE TABLE IF NOT EXISTS `persistent_vehicles` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `model` VARCHAR(64) NOT NULL,
  `plate` VARCHAR(32) NOT NULL,
  `x` DOUBLE NOT NULL DEFAULT 0,
  `y` DOUBLE NOT NULL DEFAULT 0,
  `z` DOUBLE NOT NULL DEFAULT 0,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `props` LONGTEXT NULL,
  `extra` LONGTEXT NULL,
  `last_moved` BIGINT NOT NULL DEFAULT 0,
  `lock_status` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_plate` (`plate`),
  INDEX `idx_last_moved` (`last_moved`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
