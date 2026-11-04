CREATE TABLE `app_store_notifications` (
	`notification_uuid` text PRIMARY KEY,
	`type` text NOT NULL,
	`subtype` text,
	`environment` text,
	`original_transaction_id` text,
	`outcome` text NOT NULL,
	`received_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `purchases` (
	`original_transaction_id` text PRIMARY KEY,
	`transaction_id` text NOT NULL,
	`owner_id` text NOT NULL,
	`product_id` text NOT NULL,
	`stamps` integer NOT NULL,
	`environment` text NOT NULL,
	`status` text NOT NULL,
	`refunds` integer NOT NULL,
	`flagged` integer NOT NULL,
	`purchased_at` integer NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `stamp_ledger` (
	`id` text PRIMARY KEY,
	`owner_id` text NOT NULL,
	`kind` text NOT NULL,
	`amount` integer NOT NULL,
	`product_id` text NOT NULL,
	`original_transaction_id` text NOT NULL,
	`at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `app_store_notifications_received_at_index` ON `app_store_notifications` (`received_at`);--> statement-breakpoint
CREATE INDEX `purchases_owner_id_index` ON `purchases` (`owner_id`);--> statement-breakpoint
CREATE INDEX `stamp_ledger_owner_id_index` ON `stamp_ledger` (`owner_id`,`at`);