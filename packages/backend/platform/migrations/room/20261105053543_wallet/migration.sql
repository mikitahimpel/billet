CREATE TABLE `coin_entry` (
	`seq` integer PRIMARY KEY AUTOINCREMENT,
	`id` text NOT NULL,
	`kind` text NOT NULL,
	`amount` integer NOT NULL,
	`ref` text NOT NULL,
	`at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `wallet` (
	`id` integer PRIMARY KEY,
	`balance` integer NOT NULL,
	`day` text,
	`care` integer NOT NULL,
	`notes` integer NOT NULL,
	`games` integer NOT NULL,
	CONSTRAINT "wallet_single_row" CHECK("id" = 1)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `coin_entry_id` ON `coin_entry` (`id`);