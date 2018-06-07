# -*- coding: utf-8 -*-
# Generated by Django 1.11.13 on 2018-05-29 12:20
from __future__ import unicode_literals

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('global_infos', '0001_initial'),
    ]

    operations = [
        migrations.AlterField(
            model_name='facultyadmin',
            name='g_ad_group',
            field=models.CharField(db_column='g_ad_group', max_length=50, verbose_name='Active Directory Group (short)'),
        ),
        migrations.AlterField(
            model_name='facultyadmin',
            name='g_faculty',
            field=models.CharField(db_column='g_faculty', max_length=50, primary_key=True, serialize=False, verbose_name='Faculty'),
        ),
        migrations.AlterModelTable(
            name='facultyadmin',
            table='glob_inf_faculty_admins',
        ),
    ]