-- Generated from catalog JSON. Do not edit by hand.
-- Pure data plus lookups; no hooks, SQL or requires.
local K = {}

K.CATALOG_VERSION = "lv3-book-2026-10-27.3"
K.Base = {armor = 0, healDifficulty = 8, woundLimit = 3, energySpendLimit = 6, fateDie = "1d6"}
K.MasteryPointsAtCreation = 2
K.MasteryOrder = {"skill", "knowledge", "endurance", "craft"}
K.Masteries = {
    skill = {
        key = "skill",
        name = "Навык",
        text = "Проверки, требующие отточенных рефлексов и контроля над телом. Пример: быстрое преодоление препятствий, скрытность, скалолазание.",
    },
    knowledge = {
        key = "knowledge",
        name = "Знание",
        text = "Проверки, требующие острого ума и хорошей памяти. Пример: выслеживание цели, перевод текста, оценка ситуации в гуще боя.",
    },
    endurance = {
        key = "endurance",
        name = "Упорство",
        text = "Проверки, требующие крепкого здоровья и выносливости. Пример: состязание едоков, бег наперегонки, концентрация на сложном заклинании.",
    },
    craft = {
        key = "craft",
        name = "Ремесло",
        text = "Проверки, требующие умелых рук и частой практики. Пример: создание предметов, ремонт укреплений, лечение серьёзных ран.",
    },
}
K.DieSteps = {"1d1", "1d4", "1d6", "1d8", "1d10", "1d12", "1d20"}
K.Sizes = {
    tiny = {key = "tiny", name = "Крошечный", order = 0, playable = false, speed = nil, mechanics = {}},
    small = {
        key = "small",
        name = "Маленький",
        order = 1,
        playable = true,
        speed = 12,
        mechanics = {
            {op = "add", target = "speed", value = 2, inBase = true},
            {op = "add", target = "evasion", value = 1},
            {op = "add", target = "maxHealth", value = -2},
            {op = "add", target = "resistance", value = -1},
        },
    },
    medium = {key = "medium", name = "Средний", order = 2, playable = true, speed = 10, mechanics = {}},
    large = {
        key = "large",
        name = "Большой",
        order = 3,
        playable = true,
        speed = 8,
        mechanics = {
            {op = "add", target = "maxHealth", value = 2},
            {op = "add", target = "resistance", value = 1},
            {op = "add", target = "speed", value = -2, inBase = true},
            {op = "add", target = "evasion", value = -1},
        },
    },
    huge = {key = "huge", name = "Огромный", order = 4, playable = false, speed = nil, mechanics = {}},
    gargantuan = {key = "gargantuan", name = "Чудовищный", order = 5, playable = false, speed = nil, mechanics = {}},
}
K.Xp = {
    {level = 1, serverLevel = 10, xpStart = 0, xpToNext = 20},
    {level = 2, serverLevel = 11, xpStart = 20, xpToNext = 25},
    {level = 3, serverLevel = 12, xpStart = 45, xpToNext = 30},
    {level = 4, serverLevel = 13, xpStart = 75, xpToNext = 40},
    {level = 5, serverLevel = 14, xpStart = 115, xpToNext = 50},
    {level = 6, serverLevel = 15, xpStart = 165, xpToNext = 60},
    {level = 7, serverLevel = 16, xpStart = 225, xpToNext = 75},
    {level = 8, serverLevel = 17, xpStart = 300, xpToNext = 90},
    {level = 9, serverLevel = 18, xpStart = 390, xpToNext = 110},
    {level = 10, serverLevel = 19, xpStart = 500, xpToNext = nil},
}
K.Archetypes = {
    defender = {
        key = "defender",
        name = "Защитник",
        description = "Ваш персонаж всегда готов принять удар врагов на себя. Более того, он имеет все шансы после этого выжить.",
        features = {
            {
                key = "zabiyaka",
                name = "Забияка",
                level = 1,
                text = "Персонаж получает Бонус ситуации на все действия против цели, которая пыталась его атаковать в прошлом ходу. Если по персонажу нанесли урон, но он был полностью поглощён бронёй или блокированием, восстанавливает ему 1 Энергии.",
                mechanics = {
                    {
                        op = "add",
                        target = "situation_bonus",
                        value = 1,
                        condition = "target attacked self last turn",
                        trigger = true,
                    },
                    {
                        op = "add",
                        target = "energy_restore",
                        value = 1,
                        condition = "damage fully absorbed by armor/block",
                        trigger = true,
                    },
                },
            },
        },
        levels = {
            {maxHealth = 20, maxEnergy = 8, accuracy = 0, healing = -1, evasion = 2, resistance = 1, abilitySlots = 0},
            {maxHealth = 22, maxEnergy = 9, accuracy = 0, healing = -1, evasion = 2, resistance = 1, abilitySlots = 0},
            {maxHealth = 24, maxEnergy = 10, accuracy = 0, healing = -1, evasion = 2, resistance = 1, abilitySlots = 1},
            {maxHealth = 26, maxEnergy = 11, accuracy = 0, healing = 0, evasion = 2, resistance = 1, abilitySlots = 1},
            {maxHealth = 29, maxEnergy = 12, accuracy = 0, healing = 0, evasion = 2, resistance = 1, abilitySlots = 2},
            {maxHealth = 31, maxEnergy = 13, accuracy = 1, healing = 0, evasion = 3, resistance = 2, abilitySlots = 2},
            {maxHealth = 33, maxEnergy = 14, accuracy = 1, healing = 0, evasion = 3, resistance = 2, abilitySlots = 3},
            {maxHealth = 35, maxEnergy = 15, accuracy = 1, healing = 0, evasion = 3, resistance = 2, abilitySlots = 3},
            {maxHealth = 37, maxEnergy = 16, accuracy = 1, healing = 0, evasion = 3, resistance = 2, abilitySlots = 4},
            {maxHealth = 40, maxEnergy = 18, accuracy = 2, healing = 1, evasion = 4, resistance = 3, abilitySlots = 4},
        },
    },
    fighter = {
        key = "fighter",
        name = "Боец",
        description = "Ваш персонаж предпочитает расправляться с врагами быстрее, чем они - с ним.",
        features = {
            {
                key = "iskusstvo_voyny",
                name = "Искусство войны",
                level = 1,
                text = "Персонаж добавляет свой Навык к урону Броска и Выстрела, Упорство - к урону Удара, а Знание - к урону Магических атак. Если у персонажа есть только бонус Ремесла - он получает +1 у броскам урона любого оружия.",
                mechanics = {
                    {op = "add", target = "damage.throw", value = "mastery.skill"},
                    {op = "add", target = "damage.shot", value = "mastery.skill"},
                    {op = "add", target = "damage.strike", value = "mastery.endurance"},
                    {op = "add", target = "damage.magic", value = "mastery.knowledge"},
                    {op = "add", target = "damage.anyWeapon", value = 1, condition = "only_craft_mastery"},
                },
            },
        },
        levels = {
            {maxHealth = 15, maxEnergy = 10, accuracy = 2, healing = 0, evasion = 1, resistance = -1, abilitySlots = 0},
            {maxHealth = 16, maxEnergy = 11, accuracy = 2, healing = 0, evasion = 1, resistance = 0, abilitySlots = 0},
            {maxHealth = 18, maxEnergy = 12, accuracy = 2, healing = 0, evasion = 1, resistance = 0, abilitySlots = 1},
            {maxHealth = 20, maxEnergy = 14, accuracy = 2, healing = 0, evasion = 1, resistance = 0, abilitySlots = 1},
            {maxHealth = 21, maxEnergy = 15, accuracy = 2, healing = 0, evasion = 1, resistance = 0, abilitySlots = 2},
            {maxHealth = 23, maxEnergy = 16, accuracy = 3, healing = 1, evasion = 2, resistance = 1, abilitySlots = 2},
            {maxHealth = 25, maxEnergy = 18, accuracy = 3, healing = 1, evasion = 2, resistance = 1, abilitySlots = 3},
            {maxHealth = 26, maxEnergy = 19, accuracy = 3, healing = 1, evasion = 2, resistance = 1, abilitySlots = 3},
            {maxHealth = 28, maxEnergy = 20, accuracy = 3, healing = 1, evasion = 2, resistance = 1, abilitySlots = 4},
            {maxHealth = 30, maxEnergy = 22, accuracy = 4, healing = 1, evasion = 3, resistance = 2, abilitySlots = 4},
        },
    },
    healer = {
        key = "healer",
        name = "Целитель",
        description = "Ваш персонаж сведущ в медицине и может врачевать самые тяжёлые раны союзников.",
        features = {
            {
                key = "tselebnye_chary",
                name = "Целебные чары",
                level = 1,
                text = "Персонаж получает Основное действие Врождённые чары, если у него их нет.\nЖезлы и Посохи получают возможность исцелять вместо нанесения урона, используя Сложность исцеления цели как порог сложности. Врождённые чары тоже получают эту возможность, и усиливают кость Лечения на 1 ступень.",
                mechanics = {
                    {op = "set", target = "grants.innateSpell", value = true},
                    {op = "set", target = "grants.wandStaffHeal", value = true},
                    {op = "add", target = "attack.innate.healDieStep", value = 1},
                },
            },
        },
        levels = {
            {maxHealth = 10, maxEnergy = 12, accuracy = -1, healing = 2, evasion = 0, resistance = 1, abilitySlots = 0},
            {maxHealth = 11, maxEnergy = 13, accuracy = -1, healing = 2, evasion = 0, resistance = 1, abilitySlots = 0},
            {maxHealth = 12, maxEnergy = 15, accuracy = -1, healing = 2, evasion = 0, resistance = 1, abilitySlots = 1},
            {maxHealth = 14, maxEnergy = 17, accuracy = 0, healing = 2, evasion = 0, resistance = 1, abilitySlots = 1},
            {maxHealth = 15, maxEnergy = 18, accuracy = 0, healing = 2, evasion = 0, resistance = 1, abilitySlots = 2},
            {maxHealth = 16, maxEnergy = 20, accuracy = 0, healing = 3, evasion = 1, resistance = 2, abilitySlots = 2},
            {maxHealth = 18, maxEnergy = 22, accuracy = 0, healing = 3, evasion = 1, resistance = 2, abilitySlots = 3},
            {maxHealth = 19, maxEnergy = 23, accuracy = 0, healing = 3, evasion = 1, resistance = 2, abilitySlots = 3},
            {maxHealth = 20, maxEnergy = 25, accuracy = 0, healing = 3, evasion = 1, resistance = 2, abilitySlots = 4},
            {maxHealth = 22, maxEnergy = 27, accuracy = 1, healing = 4, evasion = 2, resistance = 3, abilitySlots = 4},
        },
    },
    caster = {
        key = "caster",
        name = "Заклинатель",
        description = "Ваш персонаж отлично справляется с использованием различных заклинаний, шаман ли он, чернокнижник, жрец или маг.",
        features = {
            {
                key = "taynye_znaniya",
                name = "Тайные знания",
                level = 1,
                text = "Персонаж получает Основное действие Врождённые чары, если у него их нет, и увеличивает кость урона всех Магических атак на 1 ступень.",
                mechanics = {
                    {op = "set", target = "grants.innateSpell", value = true},
                    {op = "add", target = "attack.magic.dieStep", value = 1},
                },
            },
        },
        levels = {
            {maxHealth = 10, maxEnergy = 14, accuracy = 1, healing = 0, evasion = -1, resistance = 2, abilitySlots = 0},
            {maxHealth = 11, maxEnergy = 16, accuracy = 1, healing = 0, evasion = 0, resistance = 2, abilitySlots = 0},
            {maxHealth = 12, maxEnergy = 18, accuracy = 1, healing = 0, evasion = 0, resistance = 2, abilitySlots = 1},
            {maxHealth = 13, maxEnergy = 20, accuracy = 1, healing = 0, evasion = 0, resistance = 2, abilitySlots = 1},
            {maxHealth = 14, maxEnergy = 23, accuracy = 1, healing = 0, evasion = 0, resistance = 2, abilitySlots = 2},
            {maxHealth = 15, maxEnergy = 25, accuracy = 2, healing = 1, evasion = 1, resistance = 3, abilitySlots = 2},
            {maxHealth = 16, maxEnergy = 27, accuracy = 2, healing = 1, evasion = 1, resistance = 3, abilitySlots = 3},
            {maxHealth = 17, maxEnergy = 29, accuracy = 2, healing = 1, evasion = 1, resistance = 3, abilitySlots = 3},
            {maxHealth = 18, maxEnergy = 31, accuracy = 2, healing = 1, evasion = 1, resistance = 3, abilitySlots = 4},
            {maxHealth = 20, maxEnergy = 34, accuracy = 3, healing = 1, evasion = 2, resistance = 4, abilitySlots = 4},
        },
    },
}
K.ArchetypeOrder = {"defender", "fighter", "healer", "caster"}
K.DEFAULT_RACE_PRESET = {
    preset = "default",
    presetVersion = 1,
    feature = {
        slot = 1,
        name = "Без расовых особенностей (заглушка)",
        text = "Особенности расы ещё в разработке. После обновления пресета можно будет сбросить расовые данные.",
        mechanics = {},
    },
}
K.Races = {
    orc = {
        key = "orc",
        name = "Орк",
        size = "medium",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "krovavoe_neistovstvo",
                slot = 1,
                name = "Кровавое неистовство",
                text = "Персонаж получает +1 к Урону атак и Сопротивлению за каждую неисцелённую Рану, но его Сложность исцеления перманентно повышена на 2.",
                mechanics = {
                    {op = "add", target = "damage", value = 1, per = "unhealed_wound"},
                    {op = "add", target = "resistance", value = 1, per = "unhealed_wound"},
                    {op = "add", target = "healDifficulty", value = 2},
                },
            },
            {
                key = "vlastnost",
                slot = 2,
                name = "Властность",
                text = "Орк получает +1 к Упорству.\nСущества под его контролем повышают кость урона своих атак на 1 ступень. Кроме того, когда он отдаёт цели Команду, она получает Бонус ситуации +1 к броску, если подчинится.",
                mechanics = {
                    {op = "add", target = "mastery.endurance", value = 1},
                    {op = "add", target = "controlled_creatures.damage_die_step", value = 1},
                    {
                        op = "add",
                        target = "command.situation_bonus",
                        value = 1,
                        condition = "target_obeys",
                        trigger = true,
                    },
                },
            },
        },
    },
    troll = {
        key = "troll",
        name = "Тролль",
        size = "medium",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "regeneratsiya",
                slot = 1,
                name = "Регенерация",
                text = "Персонаж восполняет 2 Здоровья в начале каждого хода и ещё по 1 за каждую неисцелённую Рану.",
                mechanics = {
                    {op = "add", target = "health_regen_turn_start", value = 2, trigger = true},
                    {op = "add", target = "health_regen_turn_start", value = 1, per = "unhealed_wound", trigger = true},
                },
            },
            {
                key = "berserk",
                slot = 2,
                name = "Берсерк",
                text = "Броня персонажа перманентно снижена на 2. Пока он Ранен, стоимость всех Способностей дороже 2 ед. Энергии снижается на 1.",
                mechanics = {
                    {op = "add", target = "armor", value = -2},
                    {op = "add", target = "ability_cost", value = -1, condition = "wounded and ability_cost > 2"},
                },
            },
        },
    },
    tauren = {
        key = "tauren",
        name = "Таурен",
        size = "large",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "zakalka",
                slot = 1,
                name = "Закалка",
                text = "Персонаж получает дополнительно 1 ед. максимального запаса Здоровья за каждый уровень, начиная с 1. Снижает штраф к Скорости от доспехов и щитов на 1.",
                mechanics = {
                    {op = "add", target = "maxHealth", value = 1, perLevel = true},
                    {op = "add", target = "equipmentSpeedPenalty", value = -1},
                },
                todo = "TODO: «Закалка» + «Большой» и снижение штрафа — на предмет или на сумму не определено",
            },
            {
                key = "traditsii_predkov",
                slot = 2,
                name = "Традиции предков",
                text = "Таурен получает ещё 1 очко Мастерства, которое он может распределить на своё усмотрение.",
                mechanics = {
                    {op = "add", target = "masteryPointsFree", value = 1},
                },
            },
        },
    },
    forsaken = {
        key = "forsaken",
        name = "Нежить (Отрекшийся)",
        size = "medium",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "neupokoennyy",
                slot = 1,
                name = "Неупокоенный",
                text = "Персонаж получает +1 к Броне и может пережить 1 дополнительную Рану.",
                mechanics = {
                    {op = "add", target = "armor", value = 1},
                    {op = "add", target = "woundLimit", value = 1},
                },
            },
            {
                key = "vechnyy_golod",
                slot = 2,
                name = "Вечный голод",
                text = "Увеличивает кость урона Безоружной атаки и Врождённых чар на 1 ступень. Если их целью стало живое существо, при успехе такая атака похищает у него 2 ед. Здоровья.",
                mechanics = {
                    {op = "add", target = "attack.unarmed.dieStep", value = 1},
                    {op = "add", target = "attack.innate.dieStep", value = 1},
                    {
                        op = "add",
                        target = "lifesteal_health",
                        value = 2,
                        condition = "unarmed_or_innate_hit and target_alive",
                        trigger = true,
                    },
                },
            },
        },
    },
    blood_elf = {
        key = "blood_elf",
        name = "Эльф крови",
        size = "medium",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "rodstvo_s_charami",
                slot = 1,
                name = "Родство с чарами",
                text = "Персонаж получает +1 к Сопротивлению.\nЕсли он становится целью любого Магического эффекта (атака, заклинание и т.д.), то восполняет 1 единицу Энергии, даже если эффект не сработал.",
                mechanics = {
                    {op = "add", target = "resistance", value = 1},
                    {
                        op = "add",
                        target = "energy_restore",
                        value = 1,
                        condition = "targeted_by_magic_effect",
                        trigger = true,
                    },
                },
            },
            {
                key = "manaotbor",
                slot = 2,
                name = "Манаотбор",
                text = "Персонаж крадёт 1 единицу Энергии у цели при успешном прямом взаимодействии с ней. Эффект удваивается, если передача Энергии добровольна.",
                mechanics = {
                    {
                        op = "add",
                        target = "energy_steal",
                        value = 1,
                        condition = "successful_direct_interaction",
                        trigger = true,
                    },
                    {
                        op = "add",
                        target = "energy_steal",
                        value = 1,
                        condition = "energy_transfer_voluntary",
                        trigger = true,
                    },
                },
            },
        },
    },
    ogre = {
        key = "ogre",
        name = "Огр",
        size = "large",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "myasnoy_schit",
                slot = 1,
                name = "Мясной щит",
                text = "Повышает кость Блокирования персонажа на 1 ступень. Снижает штраф к Скорости от доспехов и щитов на 1.",
                mechanics = {
                    {op = "add", target = "block.dieStep", value = 1},
                    {op = "add", target = "equipmentSpeedPenalty", value = -1},
                },
                todo = "TODO: без щита база Блока 1 (кость I); повышение её ступени Мясным щитом не определено",
            },
            {
                key = "dve_golovy_luchshe",
                slot = 2,
                name = "Две головы - лучше",
                text = "Огр получает +1 к Знанию, +2 к максимуму Здоровья и Энергии и действие Врождённые чары. Вторая голова вмешивается в события в самый неподходящий момент, делая огра непредсказуемым и для окружающих, и для него самого: любой бросок 3d6 персонажа с результатом ниже 9 теперь считается провальным.",
                mechanics = {
                    {op = "add", target = "mastery.knowledge", value = 1},
                    {op = "add", target = "maxHealth", value = 2},
                    {op = "add", target = "maxEnergy", value = 2},
                    {op = "set", target = "grants.innateSpell", value = true},
                    {op = "set", target = "roll_3d6_auto_fail_below", value = 9, trigger = true},
                },
                todo = "TODO: момент проверки «ниже 9» у Огра — до или после бонусов не определён",
            },
        },
    },
    goblin = {
        key = "goblin",
        name = "Гоблин",
        size = "small",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "zhulnichestvo",
                slot = 1,
                name = "Жульничество",
                text = "Может перебросить 1 любой бросок в свой ход, но обязан принять второй результат. К этому броску нельзя добавить Кость Судьбы.",
                mechanics = {
                    {op = "set", target = "reroll_per_turn", value = 1},
                },
            },
            {
                key = "vremya_dengi",
                slot = 2,
                name = "Время - деньги",
                text = "Гоблин получает +2 Скорости и 2 дополнительных шага для Прорыва.",
                mechanics = {
                    {op = "add", target = "speed", value = 2},
                    {op = "add", target = "ability.breakthrough.extra_steps", value = 2},
                },
            },
        },
    },
    pandaren = {
        key = "pandaren",
        name = "Пандарен",
        size = "medium",
        status = "available",
        preset = "book",
        presetVersion = 1,
        features = {
            {
                key = "pivka_dlya_ryvka",
                slot = 1,
                name = "Пивка для рывка!",
                text = "Персонаж получает +1 к Уклонению и Скорости.",
                mechanics = {
                    {op = "add", target = "evasion", value = 1},
                    {op = "add", target = "speed", value = 1},
                },
            },
            {
                key = "gurman",
                slot = 2,
                name = "Гурман",
                text = "Пандарен получает +1 к Ремеслу. Все положительные эффекты, связанные с едой и питьём, вдвое сильнее, а отрицательные - вдвое слабее.",
                mechanics = {
                    {op = "add", target = "mastery.craft", value = 1},
                },
            },
        },
    },
    human = {
        key = "human",
        name = "Человек",
        size = "medium",
        status = "available",
        preset = "default",
        presetVersion = 1,
        features = {
            {
                key = "human_default",
                slot = 1,
                name = "Без расовых особенностей (заглушка)",
                text = "Особенности расы ещё в разработке. После обновления пресета можно будет сбросить расовые данные.",
                mechanics = {},
            },
        },
        bookStatus = "in_development",
    },
    high_elf = {
        key = "high_elf",
        name = "Высший эльф",
        size = "medium",
        status = "available",
        preset = "default",
        presetVersion = 1,
        features = {
            {
                key = "high_elf_default",
                slot = 1,
                name = "Без расовых особенностей (заглушка)",
                text = "Особенности расы ещё в разработке. После обновления пресета можно будет сбросить расовые данные.",
                mechanics = {},
            },
        },
        bookStatus = "in_development",
    },
    dwarf = {
        key = "dwarf",
        name = "Дворф",
        size = "medium",
        status = "available",
        preset = "default",
        presetVersion = 1,
        features = {
            {
                key = "dwarf_default",
                slot = 1,
                name = "Без расовых особенностей (заглушка)",
                text = "Особенности расы ещё в разработке. После обновления пресета можно будет сбросить расовые данные.",
                mechanics = {},
            },
        },
        bookStatus = "in_development",
    },
    night_elf = {
        key = "night_elf",
        name = "Ночной эльф",
        size = "medium",
        status = "available",
        preset = "default",
        presetVersion = 1,
        features = {
            {
                key = "night_elf_default",
                slot = 1,
                name = "Без расовых особенностей (заглушка)",
                text = "Особенности расы ещё в разработке. После обновления пресета можно будет сбросить расовые данные.",
                mechanics = {},
            },
        },
        bookStatus = "in_development",
    },
    draenei = {
        key = "draenei",
        name = "Дреней",
        size = "medium",
        status = "available",
        preset = "default",
        presetVersion = 1,
        features = {
            {
                key = "draenei_default",
                slot = 1,
                name = "Без расовых особенностей (заглушка)",
                text = "Особенности расы ещё в разработке. После обновления пресета можно будет сбросить расовые данные.",
                mechanics = {},
            },
        },
        bookStatus = "in_development",
    },
    gnome = {
        key = "gnome",
        name = "Гном",
        size = "small",
        status = "available",
        preset = "default",
        presetVersion = 1,
        features = {
            {
                key = "gnome_default",
                slot = 1,
                name = "Без расовых особенностей (заглушка)",
                text = "Особенности расы ещё в разработке. После обновления пресета можно будет сбросить расовые данные.",
                mechanics = {},
            },
        },
        bookStatus = "in_development",
    },
}
K.RaceOrder = {"orc", "troll", "tauren", "forsaken", "blood_elf", "ogre", "goblin", "pandaren", "human", "high_elf", "dwarf", "night_elf", "draenei", "gnome"}
K.Traits = {
    polnoe_pokrytie = {
        key = "polnoe_pokrytie",
        name = "Полное покрытие",
        text = "Удар по площади получает 2 дополнительных шага к радиусу.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "ability.area_strike.radius", value = 2},
        },
    },
    seriya_priemov = {
        key = "seriya_priemov",
        name = "Серия приёмов",
        text = "Лимит Энергии, которую можно использовать за ход, повышен на 2.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "energySpendLimit", value = 2},
        },
    },
    palach = {
        key = "palach",
        name = "Палач",
        text = "Если у цели остаётся 3 или меньше Здоровья после вашей успешной атаки, её Здоровье падает до 0.",
        status = "available",
        fixing = false,
        mechanics = {
            {
                op = "set",
                target = "target.health",
                value = 0,
                condition = "successful_attack and target.health <= 3",
                trigger = true,
            },
        },
    },
    lyubimets_sudby = {
        key = "lyubimets_sudby",
        name = "Любимец судьбы",
        text = "Кость Судьбы увеличивается до 1д12. Результат броска не может быть ниже Уровня персонажа +1.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "set", target = "fateDie.die", value = "1d12"},
            {op = "set", target = "fateDie.minResult", value = "level+1"},
        },
    },
    telohranitel = {
        key = "telohranitel",
        name = "Телохранитель",
        text = "Вы можете применить Концентрацию или Блок для того, чтобы переместиться к выбранному союзнику и принять атаку по нему на себя. Союзник должен находиться не далее, чем в 3 шагах от персонажа, и не должен иметь черту Телохранитель.",
        status = "available",
        fixing = false,
        mechanics = {},
        todo = "TODO: у Телохранителя нет числовой механики; триггер Блока/Концентрации за союзника не утверждён",
    },
    zhivuchest = {
        key = "zhivuchest",
        name = "Живучесть",
        text = "Персонаж может пережить ещё 1 Рану и получает +1 к броскам 3d6 при достижении лимита Ран.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "woundLimit", value = 1},
            {op = "add", target = "deathSaveBonus", value = 1},
        },
    },
    takticheskoe_preimuschestvo = {
        key = "takticheskoe_preimuschestvo",
        name = "Тактическое преимущество",
        text = "Выпавший дубль генерирует дополнительно 1 Энергии.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "energyPerDouble", value = 1},
        },
    },
    odarennost = {
        key = "odarennost",
        name = "Одарённость",
        text = "Вы получаете Персональные способности на 1 уровень раньше (2, 4, 6, 8)",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "set", target = "abilityUnlockLevels", value = {2, 4, 6, 8}},
        },
    },
    ekspert = {
        key = "ekspert",
        name = "Эксперт",
        text = "Выберите Мастерство. Любая Пороговая проверка этого Мастерства считается для вас на 1 ступень легче, а все остальные проверки получают Бонус ситуации +1.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "mastery.<chosen>.threshold_step", value = -1, condition = "threshold_check"},
            {op = "add", target = "mastery.<chosen>.situation_bonus", value = 1, condition = "non_threshold_check"},
        },
        choice = "mastery",
    },
    razmer_imeet_znachenie = {
        key = "razmer_imeet_znachenie",
        name = "Размер имеет значение",
        text = "Вы получаете бонус +1 ко всем броскам против целей, которые вы превосходите по размеру. Если вы Маленького размера, то теперь считаетесь существом Среднего размера.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "all_rolls", value = 1, condition = "target.size < self.size"},
            {op = "set", target = "size", value = "medium", condition = "self.size == small"},
        },
    },
    moguchee_teloslozhenie = {
        key = "moguchee_teloslozhenie",
        name = "Могучее телосложение",
        text = "За каждый уровень персонажа, начиная с первого, он получает дополнительно 1 ед. максимального Здоровья.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "maxHealth", value = 1, perLevel = true},
        },
    },
    vezunchik = {
        key = "vezunchik",
        name = "Везунчик",
        text = "Если в любом броске выпала единица, можно перебросить его раз за ход. Вы обязаны принять второй результат.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "set", target = "reroll_die_showing_1_per_turn", value = 1},
        },
    },
    meditatsiya = {
        key = "meditatsiya",
        name = "Медитация",
        text = "Передышка восстанавливает 1d6 Энергии и 1d4 Здоровья.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "set", target = "action.respite.energy_restore", value = "1d6"},
            {op = "set", target = "action.respite.health_restore", value = "1d4"},
        },
    },
    zaschita_ot_magii = {
        key = "zaschita_ot_magii",
        name = "Защита от магии",
        text = "Ваш бонус к Сопротивлению становится равен +2. Ваше Сопротивление не может превысить этот бонус никаким способом, даже расовой особенностью, временными усилениями и экипировкой.",
        status = "available",
        fixing = true,
        mechanics = {
            {op = "set", target = "resistance", value = 2},
            {op = "cap", target = "resistance", value = 2},
        },
    },
    refleksy_kobry = {
        key = "refleksy_kobry",
        name = "Рефлексы кобры",
        text = "Ваш бонус к Уклонению становится равен +2. Ваше Уклонение не может превысить этот бонус никаким способом, даже расовой особенностью, временными усилениями и экипировкой.",
        status = "available",
        fixing = true,
        mechanics = {
            {op = "set", target = "evasion", value = 2},
            {op = "cap", target = "evasion", value = 2},
        },
    },
    boevoy_opyt = {
        key = "boevoy_opyt",
        name = "Боевой опыт",
        text = "Ваш бонус к Меткости становится равен +2. Ваша Меткость не может превысить этот бонус никаким способом, даже расовой особенностью, временными усилениями и экипировкой.",
        status = "available",
        fixing = true,
        mechanics = {
            {op = "set", target = "accuracy", value = 2},
            {op = "cap", target = "accuracy", value = 2},
        },
    },
    prirozhdennyy_lekar = {
        key = "prirozhdennyy_lekar",
        name = "Прирождённый лекарь",
        text = "Ваш бонус к Исцелению становится равен +2. Ваше Исцеление не может превысить этот бонус никаким способом, даже расовой особенностью, временными усилениями и экипировкой.",
        status = "available",
        fixing = true,
        mechanics = {
            {op = "set", target = "healing", value = 2},
            {op = "cap", target = "healing", value = 2},
        },
    },
    okno_vozmozhnostey = {
        key = "okno_vozmozhnostey",
        name = "Окно возможностей",
        text = "Атака по возможности при дубле может накопить 1 ОЭ.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "set", target = "opportunity_attack.energy_on_double", value = 1},
        },
    },
    razmer_ne_glavnoe = {
        key = "razmer_ne_glavnoe",
        name = "Размер - не главное",
        text = "+1 ко всем броскам против целей, равным или превосходящим вас по размеру.",
        status = "available",
        fixing = false,
        mechanics = {
            {op = "add", target = "all_rolls", value = 1, condition = "target.size >= self.size"},
        },
    },
    taran = {
        key = "taran",
        name = "Таран",
        text = "Наносит 1д6 неблокируемого урона цели, если перед этим было пройдено не менее 5 шагов и цели можно коснуться. 1 раз за ход.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    odinochka = {
        key = "odinochka",
        name = "Одиночка",
        text = "+1 ко всем броскам, если в радиусе 5 шагов нет союзников.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "all_rolls", value = 1, condition = "no_allies_within_5_steps"},
        },
    },
    pogromschik = {
        key = "pogromschik",
        name = "Погромщик",
        text = "Вы наносите 1д6 дополнительного неблокируемого урона от всех источников Големам и Механизмам, а так же заграждениям (двери и баррикады) и тотемам.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    neutomimost = {
        key = "neutomimost",
        name = "Неутомимость",
        text = "Максимальный запас ОЭ повышается на 2.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "maxEnergy", value = 2},
        },
    },
    ni_shagu_nazad = {
        key = "ni_shagu_nazad",
        name = "Ни шагу назад",
        text = "+2 ко всем броскам в бою, если у вас есть Рана. Дополнительно даёт +1 к Защите и Сопротивлению, если Ран две.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "combat_rolls", value = 2, condition = "wounds >= 1"},
            {op = "add", target = "evasion", value = 1, condition = "wounds >= 2"},
            {op = "add", target = "resistance", value = 1, condition = "wounds >= 2"},
        },
    },
    ratsionalnost = {
        key = "ratsionalnost",
        name = "Рациональность",
        text = "Избыточный урон и исцеление, исходящие от вас, переносятся на ближайшее к цели существо на ваш выбор.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    prizyvatel = {
        key = "prizyvatel",
        name = "Призыватель",
        text = "Призванные существа существуют на 1 ход дольше, а постоянные питомцы получают +1 ко ВСЕМ своим броскам.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    zveroboy = {
        key = "zveroboy",
        name = "Зверобой",
        text = "+2 ко всем броскам против Зверей",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "all_rolls", value = 2, condition = "target.type == beast"},
        },
    },
    polevaya_meditsina = {
        key = "polevaya_meditsina",
        name = "Полевая медицина",
        text = "Прилив сил теперь восполняет 1д6 ОЗ и его возможно применить на союзную цель, если персонаж может её коснуться. Сложность Исцеления этой цели выше на 2.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    vybros_adrenalina = {
        key = "vybros_adrenalina",
        name = "Выброс адреналина",
        text = "Усиление и Прилив сил получают бонус +1",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "ability.empower.bonus", value = 1},
            {op = "add", target = "ability.second_wind.bonus", value = 1},
        },
    },
    bez_tormozov = {
        key = "bez_tormozov",
        name = "Без тормозов",
        text = "Если вы истратили не все шаги передвижения в этом ходу, вы невосприимчивы к Замедлению и Обездвиживанию до начала своего следующего хода и получаете 3 дополнительных шага движения в нём.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    kavalerist = {
        key = "kavalerist",
        name = "Кавалерист",
        text = "+2 ко всем броскам в бою, если вы в седле.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "combat_rolls", value = 2, condition = "mounted"},
        },
    },
    ekzortsist = {
        key = "ekzortsist",
        name = "Экзорцист",
        text = "Вы имеете бонус +5 на атаки против Демонов и Нежити, а так же наносите им 1д4 дополнительного неблокируемого урона от всех источников.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "attack_rolls", value = 5, condition = "target.type in (demon, undead)"},
        },
    },
    pobednyy_razh = {
        key = "pobednyy_razh",
        name = "Победный раж",
        text = "+2 ОЗ, если рядом погибает враждебное существо. +5 ОЗ - если смертельный удар нанесли вы. 1 раз за ход.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "health", value = 2, condition = "enemy_dies_nearby"},
            {op = "add", target = "health", value = 5, condition = "self_killing_blow"},
        },
    },
    zatmitel_nebes = {
        key = "zatmitel_nebes",
        name = "Затмитель небес",
        text = "Ваша успешная атака по летающей цели заставляет её приземлиться в начале её следующего хода и получить Обездвиживание на 1 ход.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    instinkt_samosohraneniya = {
        key = "instinkt_samosohraneniya",
        name = "Инстинкт самосохранения",
        text = "Первый Блок или Защита за ход стоит на 1 ОЭ меньше.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "first_block_cost_per_turn", value = -1},
        },
    },
    prirozhdennyy_lekar_rework = {
        key = "prirozhdennyy_lekar_rework",
        name = "Прирождённый лекарь",
        text = "Персонаж получает бонус к Исцелению +1, удачное исцеление другого существа восстанавливает ему +1 ОЗ.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "healing", value = 1},
            {op = "add", target = "heal_other.extra_health_self", value = 1},
        },
    },
    fontan_krovi = {
        key = "fontan_krovi",
        name = "Фонтан крови",
        text = "Восстанавливает 3 ОЭ, если рядом кто-то гибнет под эффектом Кровотечения или от Раны",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "energy", value = 3, condition = "someone_dies_nearby_from_bleed_or_wound"},
        },
    },
    falanga = {
        key = "falanga",
        name = "Фаланга",
        text = "+1 ОЗ за каждого союзника в группе и +1 Физической и Магической защиты, если группа полна.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    vo_vseoruzhii = {
        key = "vo_vseoruzhii",
        name = "Во всеоружии",
        text = "Атака, совершённая после Смены оружия или Перезарядки, нанесёт дополнительно 3 урона и сгенерирует 1 ОЭ. Смена оружия на другое не затрачивает Дополнительное действие. Один раз за ход.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "damage", value = 3, condition = "attack_after_weapon_swap_or_reload"},
        },
    },
    master_zasad = {
        key = "master_zasad",
        name = "Мастер засад",
        text = "После совершённой этим персонажем атаки из Скрытности один ближайший к цели союзник может совершить Атаку по возможности по этой же цели. Если союзников рядом с целью нет, персонаж совершает её сам. Лидер отряда может прибавить +1 к ситуации при броске инициативы за каждого персонажа с этой чертой.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
    beshitrostnost = {
        key = "beshitrostnost",
        name = "Бесхитростность",
        text = "Вы можете выбрать 2 Общих Черты в дополнение к этой, но лишаетесь доступа к Персональным способностям. Максимальный запас ОЭ сокращается на 1.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "general_traits_extra", value = 2},
            {op = "set", target = "personal_abilities_disabled", value = true},
            {op = "add", target = "maxEnergy", value = -1},
        },
    },
    perepolnyayuschaya_mosch = {
        key = "perepolnyayuschaya_mosch",
        name = "Переполняющая мощь",
        text = "Смертельный удар и Великое исцеление дешевле на 1 ОЭ.",
        status = "in_development",
        fixing = false,
        mechanics = {
            {op = "add", target = "ability.killing_blow.cost", value = -1},
            {op = "add", target = "ability.great_heal.cost", value = -1},
        },
    },
    gruppovaya_ohota = {
        key = "gruppovaya_ohota",
        name = "Групповая охота",
        text = "Если хозяин может коснуться своего питомца, то Команду можно отдать Дополнительным действием вместо Основного.",
        status = "in_development",
        fixing = false,
        mechanics = {},
    },
}
K.TraitOrder = {"polnoe_pokrytie", "seriya_priemov", "palach", "lyubimets_sudby", "telohranitel", "zhivuchest", "takticheskoe_preimuschestvo", "odarennost", "ekspert", "razmer_imeet_znachenie", "moguchee_teloslozhenie", "vezunchik", "meditatsiya", "zaschita_ot_magii", "refleksy_kobry", "boevoy_opyt", "prirozhdennyy_lekar", "okno_vozmozhnostey", "razmer_ne_glavnoe", "taran", "odinochka", "pogromschik", "neutomimost", "ni_shagu_nazad", "ratsionalnost", "prizyvatel", "zveroboy", "polevaya_meditsina", "vybros_adrenalina", "bez_tormozov", "kavalerist", "ekzortsist", "pobednyy_razh", "zatmitel_nebes", "instinkt_samosohraneniya", "prirozhdennyy_lekar_rework", "fontan_krovi", "falanga", "vo_vseoruzhii", "master_zasad", "beshitrostnost", "perepolnyayuschaya_mosch", "gruppovaya_ohota"}
K.PersonalAbilitySlots = {
    {slot = 1, unlockLevel = 3, cost = 2},
    {slot = 2, unlockLevel = 5, cost = 3},
    {slot = 3, unlockLevel = 7, cost = 4},
    {slot = 4, unlockLevel = 9, cost = 6},
}
K.GiftedUnlockLevels = {2, 4, 6, 8}
K.GeneralAbilities = {
    {
        key = "proryv",
        name = "Прорыв",
        kind = "general",
        cost = 1,
        actionType = "свободное",
        text = "Персонаж получает дополнительные шаги Движения, равные половине его Скорости. Пока персонаж использует их, он не может стать целью Атак по возможности. Можно применить 1 раз за ход.",
    },
    {
        key = "usilenie",
        name = "Усиление",
        kind = "general",
        cost = 2,
        actionType = "Ответное",
        text = "Добавляет к броску Урона, Очищения или Лечения 1d6.",
    },
    {
        key = "blok",
        name = "Блок",
        kind = "general",
        cost = 2,
        actionType = "Ответное",
        text = "Персонаж блокирует входящий урон вместо попытки от него уклониться. Объём блокируемого урона зависит от экипировки и Сопротивления персонажа.",
    },
    {
        key = "priliv_sil",
        name = "Прилив сил",
        kind = "general",
        cost = 3,
        actionType = "свободное",
        text = "Вы пользуетесь секундной передышкой, чтобы восстановить себе 1d4 ОЗ. Этой способностью можно воспользоваться даже с 0 ОЗ, приведя себя в чувство после Раны.",
    },
    {
        key = "udar_po_ploschadi",
        name = "Удар по площади",
        kind = "general",
        cost = 5,
        actionType = "Ответное",
        text = "Вы выбираете ещё две цели в радиусе 2 шагов от изначальной. Результат этого броска и последующего броска Урона, Очищения или Лечения (если бросок и для них будет успешным) распространится по ним.",
    },
    {
        key = "kontsentratsiya",
        name = "Концентрация",
        kind = "general",
        cost = 4,
        actionType = "Ответное",
        text = "Рассеивает все действующие на персонажа эффекты контроля.",
    },
    {
        key = "uskorenie",
        name = "Ускорение",
        kind = "general",
        cost = 3,
        actionType = "свободное",
        text = "Вы можете совершить ещё одну Атаку, Исцеление, Движение или Перезарядку. За дубли этих действий вы не получаете Энергию.",
    },
    {
        key = "kost_sudby",
        name = "Кость Судьбы",
        kind = "general",
        cost = 3,
        actionType = "свободное",
        text = "Вы добавляете 1d6 к результату следующего броска до конца хода или к результату последнего - так, например, можно добиться успеха при провале броска. Один раз за ход.",
    },
    {
        key = "large_shield_full_block",
        name = "Полный блок (Большой щит)",
        kind = "equipment",
        cost = 4,
        actionType = "Ответное",
        text = "Добавляет опцию при Защите: полностью поглотить урон атаки за 4 Энергии.",
    },
}
K.Qualities = {
    poor = {key = "poor", name = "Плохое", modifier = -1, starterAllowed = false},
    simple = {key = "simple", name = "Простое", modifier = 0, starterAllowed = true},
    quality = {key = "quality", name = "Качественное", modifier = 1, starterAllowed = false},
}
K.AttackRanges = {strike = 1, throw = 10, shot = 15, magic = 20}
K.Weapons = {
    one_handed_obychnoe = {
        key = "one_handed_obychnoe",
        group = "Одноручное оружие",
        hands = 1,
        property = "Обычное",
        dice = {strike = "1d8", throw = "1d1"},
    },
    one_handed_metatelnoe = {
        key = "one_handed_metatelnoe",
        group = "Одноручное оружие",
        hands = 1,
        property = "Метательное",
        dice = {strike = "1d6", throw = "1d6"},
        fullThrow = true,
    },
    one_handed_dlinnoe = {
        key = "one_handed_dlinnoe",
        group = "Одноручное оружие",
        hands = 1,
        property = "Длинное",
        dice = {strike = "1d6", throw = "1d1"},
        strikeRangeMultiplier = 2,
    },
    one_handed_magicheskoe = {
        key = "one_handed_magicheskoe",
        group = "Одноручное оружие",
        hands = 1,
        property = "Магическое",
        dice = {strike = "1d1", throw = "1d1", magic = "1d4"},
        magicEnergyCost = 1,
    },
    one_handed_strelkovoe = {
        key = "one_handed_strelkovoe",
        group = "Одноручное оружие",
        hands = 1,
        property = "Стрелковое",
        dice = {strike = "1d4", throw = "1d1", shot = "1d6"},
        reload = "quick",
        bookTypos = {"poor.strike: 0-1 (ожидалось 0-3 (Простое 1-4 -1))"},
        todo = "TODO: опечатки диапазонов; используется кость Простого ± качество",
    },
    one_handed_porohovoe = {
        key = "one_handed_porohovoe",
        group = "Одноручное оружие",
        hands = 1,
        property = "Пороховое",
        dice = {strike = "1d4", throw = "1d1", shot = "2d6"},
        reload = "full",
    },
    two_handed_obychnoe = {
        key = "two_handed_obychnoe",
        group = "Двуручное оружие",
        hands = 2,
        property = "Обычное",
        dice = {strike = "1d12", throw = "1d4"},
    },
    two_handed_dlinnoe = {
        key = "two_handed_dlinnoe",
        group = "Двуручное оружие",
        hands = 2,
        property = "Длинное",
        dice = {strike = "1d10", throw = "1d4"},
        strikeRangeMultiplier = 3,
    },
    two_handed_magicheskoe = {
        key = "two_handed_magicheskoe",
        group = "Двуручное оружие",
        hands = 2,
        property = "Магическое",
        dice = {strike = "1d6", throw = "1d4", magic = "1d6"},
        magicEnergyCost = 2,
    },
    two_handed_dalnoboynoe = {
        key = "two_handed_dalnoboynoe",
        group = "Двуручное оружие",
        hands = 2,
        property = "Дальнобойное",
        dice = {strike = "1d1", throw = "1d1", shot = "1d8"},
    },
    two_handed_strelkovoe = {
        key = "two_handed_strelkovoe",
        group = "Двуручное оружие",
        hands = 2,
        property = "Стрелковое",
        dice = {strike = "1d4", throw = "1d1", shot = "1d10"},
        reload = "quick",
        bookTypos = {"poor.shot: 0-5 урона (ожидалось 0-9 (Простое 1-10 -1))"},
        todo = "TODO: опечатки диапазонов; используется кость Простого ± качество",
    },
    two_handed_porohovoe = {
        key = "two_handed_porohovoe",
        group = "Двуручное оружие",
        hands = 2,
        property = "Пороховое",
        dice = {strike = "1d6", throw = "1d1", shot = "3d6"},
        reload = "full",
        bookTypos = {"poor.shot: 1-11 урона (ожидалось 2-17 (Простое 3-18 -1))"},
        todo = "TODO: опечатки диапазонов; используется кость Простого ± качество",
    },
}
K.Shields = {
    shield_malyy = {key = "shield_malyy", name = "Щит малый", hands = 1, blockDie = "1d4", mechanics = {}},
    shield_sredniy = {
        key = "shield_sredniy",
        name = "Щит средний",
        hands = 1,
        blockDie = "1d6",
        mechanics = {
            {op = "add", target = "evasion", value = -1},
            {op = "add", target = "speed", value = -1},
        },
    },
    shield_bolshoy = {
        key = "shield_bolshoy",
        name = "Щит большой",
        hands = 1,
        blockDie = "1d8",
        mechanics = {
            {op = "add", target = "evasion", value = -2},
            {op = "add", target = "speed", value = -2},
        },
        fullBlockCost = 4,
    },
}
K.Armor = {
    armor_legkiy = {
        key = "armor_legkiy",
        name = "Доспех лёгкий",
        armor = 2,
        mechanics = {
            {op = "add", target = "evasion", value = -1},
            {op = "add", target = "speed", value = -1},
        },
    },
    armor_tyazhelyy = {
        key = "armor_tyazhelyy",
        name = "Доспех тяжёлый",
        armor = 4,
        mechanics = {
            {op = "add", target = "evasion", value = -2},
            {op = "add", target = "speed", value = -2},
        },
    },
}
K.StarterKit = {maxItems = 6, quality = "simple"}

local OPS = {add = true, set = true, cap = true}
local FIXING_STATS = {accuracy = true, healing = true, evasion = true, resistance = true}

function K.Archetype(key) return type(key) == "string" and K.Archetypes[key] or nil end
function K.Race(key) return type(key) == "string" and K.Races[key] or nil end
function K.Trait(key) return type(key) == "string" and K.Traits[key] or nil end
function K.Size(key) return type(key) == "string" and K.Sizes[key] or nil end

function K.ArchetypeLevel(key, rpLevel)
    local arch = K.Archetype(key)
    return arch and type(rpLevel) == "number" and arch.levels[rpLevel] or nil
end

-- Returns feature, race key. The race key tells a foreign feature from an unknown one.
function K.RacialFeature(key)
    if type(key) ~= "string" then return nil end
    for _, raceKey in ipairs(K.RaceOrder) do
        for _, feature in ipairs(K.Races[raceKey].features) do
            if feature.key == key then return feature, raceKey end
        end
    end
end

function K.Available(entry) return entry ~= nil and entry.status == "available" end

-- 0 for an unknown race; a stored version below the current one means the race preset was updated.
function K.RacePresetVersion(key)
    local race = K.Race(key)
    return race and race.presetVersion or 0
end

function K.RpLevelFromServerLevel(level)
    if type(level) ~= "number" or level % 1 ~= 0 or level < 10 then return nil end
    return math.min(level - 9, #K.Xp)
end

function K.ServerLevelFromRpLevel(rpLevel)
    local row = type(rpLevel) == "number" and K.Xp[rpLevel]
    return row and row.serverLevel or nil
end

function K.LevelForXp(xp)
    if type(xp) ~= "number" or xp < 0 then return nil end
    local level = 1
    for _, row in ipairs(K.Xp) do if xp >= row.xpStart then level = row.level end end
    return level
end

function K.DieStepIndex(die)
    for index, value in ipairs(K.DieSteps) do if value == die then return index end end
end

-- Shift a single die along the I..VII ladder; dice outside the ladder stay unchanged.
function K.StepDie(die, steps)
    local index = K.DieStepIndex(die)
    if not index or steps == 0 then return die, index ~= nil end
    return K.DieSteps[math.max(1, math.min(#K.DieSteps, index + steps))], true
end

-- Self-check of the embedded data. Returns a list of error strings (empty = valid).
function K.Validate()
    local errors = {}
    local function check(ok, message) if not ok then errors[#errors + 1] = message end end
    local function mechanicsOk(owner, list)
        for i, m in ipairs(list or {}) do
            check(OPS[m.op] and type(m.target) == "string" and m.value ~= nil, owner .. ":mechanic:" .. i)
        end
    end
    for _, key in ipairs(K.ArchetypeOrder) do
        local arch = K.Archetypes[key]
        check(arch and #arch.levels == #K.Xp, "archetype:" .. key .. ":levels")
        for level, row in ipairs(arch and arch.levels or {}) do
            for _, stat in ipairs({"maxHealth", "maxEnergy", "accuracy", "healing", "evasion", "resistance",
                "abilitySlots"}) do
                check(type(row[stat]) == "number" and row[stat] % 1 == 0, "archetype:" .. key .. ":" .. level .. ":" .. stat)
            end
        end
        for _, feature in ipairs(arch and arch.features or {}) do mechanicsOk("archetype:" .. key, feature.mechanics) end
    end
    local available, defaults = 0, 0
    for _, key in ipairs(K.RaceOrder) do
        local race = K.Races[key]
        check(K.Sizes[race.size] and K.Sizes[race.size].playable, "race:" .. key .. ":size")
        check(type(race.presetVersion) == "number" and race.presetVersion % 1 == 0 and race.presetVersion >= 1,
            "race:" .. key .. ":presetVersion")
        if K.Available(race) then available = available + 1 end
        if race.preset == "default" then
            defaults = defaults + 1
            check(#race.features == 1 and race.features[1].key == key .. "_default"
                and #race.features[1].mechanics == 0, "race:" .. key .. ":default_preset")
        else
            check(race.preset == "book" and #race.features == 2, "race:" .. key .. ":features")
        end
        for _, feature in ipairs(race.features) do mechanicsOk("race:" .. key .. ":" .. feature.key, feature.mechanics) end
    end
    check(available == 14 and defaults == 6, "races:available")
    available = 0
    for _, key in ipairs(K.TraitOrder) do
        local trait = K.Traits[key]
        if K.Available(trait) then available = available + 1 end
        mechanicsOk("trait:" .. key, trait.mechanics)
        if trait.fixing then
            local set, cap = 0, 0
            for _, m in ipairs(trait.mechanics) do
                if m.op == "set" and FIXING_STATS[m.target] and m.value == 2 then set = set + 1 end
                if m.op == "cap" and FIXING_STATS[m.target] and m.value == 2 then cap = cap + 1 end
            end
            check(set == 1 and cap == 1, "trait:" .. key .. ":fixing")
        end
    end
    check(available == 19, "traits:available")
    local previous = -1
    for level, row in ipairs(K.Xp) do
        check(row.level == level and row.serverLevel == level + 9 and row.xpStart > previous, "xp:" .. level)
        previous = row.xpStart
    end
    check(K.Xp[#K.Xp] and K.Xp[#K.Xp].xpStart == 500, "xp:cap")
    check(#K.PersonalAbilitySlots == 4 and #K.GiftedUnlockLevels == 4, "abilities:slots")
    for key, weapon in pairs(K.Weapons) do
        for mode, die in pairs(weapon.dice) do check(K.AttackRanges[mode] and die:match("^%d+d%d+$"), "weapon:" .. key .. ":" .. mode) end
    end
    check(K.Weapons.two_handed_obychnoe and K.Weapons.two_handed_obychnoe.dice.strike == "1d12", "weapon:two_handed_strike")
    return errors
end

return K
