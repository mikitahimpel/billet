CREATE TABLE `blocks` (
	`blocker_id` text NOT NULL,
	`blocked_id` text NOT NULL,
	`created_at` integer NOT NULL,
	CONSTRAINT `blocks_pk` PRIMARY KEY(`blocker_id`, `blocked_id`)
);
--> statement-breakpoint
CREATE TABLE `partner_reports` (
	`id` text PRIMARY KEY,
	`reporter_id` text NOT NULL,
	`reported_id` text NOT NULL,
	`pair_id` text NOT NULL,
	`reason` text NOT NULL,
	`details` text,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `blocks_blocked_id_index` ON `blocks` (`blocked_id`);--> statement-breakpoint
CREATE INDEX `partner_reports_reported_id_index` ON `partner_reports` (`reported_id`);