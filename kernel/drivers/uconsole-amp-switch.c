// SPDX-License-Identifier: GPL-2.0-only
/*
 * ClockworkPi uConsole speaker amplifier switch
 *
 * GPIO10 (HP_DET) is high when a 3.5 mm plug is inserted.
 * GPIO11 (PA_EN) is high to enable the internal speaker amplifier.
 *
 * Keep speaker routing in-kernel and event-driven: a threaded GPIO IRQ
 * updates PA_EN whenever the headphone-detect state changes.
 */

#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>

struct uconsole_amp_switch {
	struct device *dev;
	struct gpio_desc *headphone_detect;
	struct gpio_desc *amplifier_enable;
};

static int uconsole_amp_switch_update(struct uconsole_amp_switch *amp)
{
	int headphones_inserted;

	headphones_inserted =
		gpiod_get_value_cansleep(amp->headphone_detect);
	if (headphones_inserted < 0)
		return headphones_inserted;

	gpiod_set_value_cansleep(amp->amplifier_enable,
				!headphones_inserted);

	return 0;
}

static irqreturn_t uconsole_amp_switch_irq_thread(int irq, void *data)
{
	struct uconsole_amp_switch *amp = data;
	int ret;

	ret = uconsole_amp_switch_update(amp);
	if (ret)
		dev_warn_ratelimited(amp->dev,
				     "failed to update amplifier state: %d\n",
				     ret);

	return IRQ_HANDLED;
}

static int uconsole_amp_switch_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct uconsole_amp_switch *amp;
	int irq;
	int ret;

	amp = devm_kzalloc(dev, sizeof(*amp), GFP_KERNEL);
	if (!amp)
		return -ENOMEM;

	amp->dev = dev;

	amp->headphone_detect =
		devm_gpiod_get(dev, "headphone-detect", GPIOD_IN);
	if (IS_ERR(amp->headphone_detect))
		return dev_err_probe(dev, PTR_ERR(amp->headphone_detect),
				     "failed to get headphone-detect GPIO\n");

	/*
	 * Start safe: keep the speaker amplifier disabled until the input
	 * state has been read successfully.
	 */
	amp->amplifier_enable =
		devm_gpiod_get(dev, "amplifier-enable", GPIOD_OUT_LOW);
	if (IS_ERR(amp->amplifier_enable))
		return dev_err_probe(dev, PTR_ERR(amp->amplifier_enable),
				     "failed to get amplifier-enable GPIO\n");

	irq = gpiod_to_irq(amp->headphone_detect);
	if (irq < 0)
		return dev_err_probe(dev, irq,
				     "failed to map headphone-detect IRQ\n");

	ret = devm_request_threaded_irq(dev, irq, NULL,
					uconsole_amp_switch_irq_thread,
					IRQF_ONESHOT |
					IRQF_TRIGGER_RISING |
					IRQF_TRIGGER_FALLING,
					dev_name(dev), amp);
	if (ret)
		return dev_err_probe(dev, ret,
				     "failed to request headphone-detect IRQ\n");

	platform_set_drvdata(pdev, amp);

	ret = uconsole_amp_switch_update(amp);
	if (ret)
		return dev_err_probe(dev, ret,
				     "failed to set initial amplifier state\n");

	return 0;
}

static void uconsole_amp_switch_shutdown(struct platform_device *pdev)
{
	struct uconsole_amp_switch *amp = platform_get_drvdata(pdev);

	gpiod_set_value_cansleep(amp->amplifier_enable, 0);
}

static const struct of_device_id uconsole_amp_switch_of_match[] = {
	{ .compatible = "clockworkpi,uconsole-amplifier-switch" },
	{ }
};
MODULE_DEVICE_TABLE(of, uconsole_amp_switch_of_match);

static struct platform_driver uconsole_amp_switch_driver = {
	.probe = uconsole_amp_switch_probe,
	.shutdown = uconsole_amp_switch_shutdown,
	.driver = {
		.name = "uconsole-amplifier-switch",
		.of_match_table = uconsole_amp_switch_of_match,
	},
};
module_platform_driver(uconsole_amp_switch_driver);

MODULE_DESCRIPTION("ClockworkPi uConsole headphone/speaker amplifier switch");
MODULE_LICENSE("GPL");
