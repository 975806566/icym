

DROP DATABASE IF EXISTS `im_off_db`;
create database `im_off_db`;

use `im_off_db`;

DROP TABLE IF EXISTS `msg_tmp`;
CREATE TABLE `msg_tmp` (
  `msg_id` bigint(20) unsigned NOT NULL,
  `from_id` varchar(50) NOT NULL,
  `topic` varchar(64) NOT NULL,
  `content` blob NOT NULL,
  `type` char(1) NOT NULL,
  `qos` tinyint(4) NOT NULL,
  `time` bigint(20) NOT NULL,
  PRIMARY KEY (`msg_id`),
  KEY `time` (`time`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `off_msg`;
CREATE TABLE `off_msg` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` varchar(50) COLLATE utf8_bin NOT NULL,
  `msg_id` bigint(20) unsigned NOT NULL,
  `type` char(1) COLLATE utf8_bin NOT NULL,
  `time` bigint(20) NOT NULL,
  `qos` tinyint(4) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `user_id` (`user_id`) USING HASH,
  KEY `off_time` (`time`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

