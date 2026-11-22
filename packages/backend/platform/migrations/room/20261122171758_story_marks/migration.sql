CREATE TABLE `story_marks` (
	`member` text NOT NULL,
	`episode` text NOT NULL,
	`kind` text NOT NULL,
	`ref` text NOT NULL,
	`at` integer NOT NULL,
	CONSTRAINT `story_marks_pk` PRIMARY KEY(`member`, `episode`, `kind`, `ref`)
);
