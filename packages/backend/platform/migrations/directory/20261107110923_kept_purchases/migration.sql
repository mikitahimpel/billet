CREATE TABLE `kept_items` (
	`user_id` text NOT NULL,
	`kind` text NOT NULL,
	`item_id` text NOT NULL,
	CONSTRAINT `kept_items_pk` PRIMARY KEY(`user_id`, `kind`, `item_id`)
);
--> statement-breakpoint
CREATE TABLE `kept_wallets` (
	`user_id` text PRIMARY KEY,
	`coins` integer NOT NULL
);
