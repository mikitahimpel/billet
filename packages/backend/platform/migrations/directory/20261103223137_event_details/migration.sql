CREATE TABLE `event_details` (
	`name` text NOT NULL,
	`detail` text NOT NULL,
	`day` text NOT NULL,
	`count` integer NOT NULL,
	`total` integer NOT NULL,
	CONSTRAINT `event_details_pk` PRIMARY KEY(`name`, `detail`, `day`)
);
--> statement-breakpoint
CREATE INDEX `event_details_day_index` ON `event_details` (`day`);