CREATE TABLE `plus_parcels` (
	`id` text PRIMARY KEY,
	`payer` text NOT NULL,
	`transaction_id` text NOT NULL,
	`pair_id` text NOT NULL,
	`offer` text NOT NULL,
	`price` integer NOT NULL,
	`opened_by` text NOT NULL,
	`opened_at` integer NOT NULL,
	`status` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `plus_periods` (
	`transaction_id` text PRIMARY KEY,
	`original_transaction_id` text NOT NULL,
	`user_id` text NOT NULL,
	`product_id` text NOT NULL,
	`purchased_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`revoked_at` integer
);
--> statement-breakpoint
CREATE TABLE `plus_subscriptions` (
	`original_transaction_id` text PRIMARY KEY,
	`user_id` text NOT NULL,
	`product_id` text NOT NULL,
	`environment` text NOT NULL,
	`expires_at` integer NOT NULL,
	`auto_renew` integer NOT NULL,
	`grace_until` integer,
	`revoked_at` integer,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `plus_parcels_payer_index` ON `plus_parcels` (`payer`);--> statement-breakpoint
CREATE INDEX `plus_parcels_transaction_id_index` ON `plus_parcels` (`transaction_id`);--> statement-breakpoint
CREATE INDEX `plus_periods_user_id_index` ON `plus_periods` (`user_id`);--> statement-breakpoint
CREATE INDEX `plus_subscriptions_user_id_index` ON `plus_subscriptions` (`user_id`);