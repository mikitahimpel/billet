ALTER TABLE `stamp_ledger` RENAME TO `coin_ledger`;--> statement-breakpoint
ALTER TABLE `purchases` RENAME COLUMN `stamps` TO `coins`;--> statement-breakpoint
DROP INDEX IF EXISTS `stamp_ledger_owner_id_index`;--> statement-breakpoint
CREATE INDEX `coin_ledger_owner_id_index` ON `coin_ledger` (`owner_id`,`at`);