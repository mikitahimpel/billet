ALTER TABLE `note` ADD `author` text;--> statement-breakpoint
ALTER TABLE `note` ADD `idempotency_key` text;--> statement-breakpoint
CREATE UNIQUE INDEX `note_author_key` ON `note` (`author`,`idempotency_key`);