# -*- coding: utf-8 -*-
__copyright__ = "Copyright (C) 2013 David Braam - Released under terms of the AGPLv3 License"

import wx
import time
import sys
import os
import ctypes

#TODO: This does not belong here!
if sys.platform.startswith('win'):
	def preventComputerFromSleeping(prevent):
		"""
		Function used to prevent the computer from going into sleep mode.
		:param prevent: True = Prevent the system from going to sleep from this point on.
		:param prevent: False = No longer prevent the system from going to sleep.
		"""
		ES_CONTINUOUS = 0x80000000
		ES_SYSTEM_REQUIRED = 0x00000001
		#SetThreadExecutionState returns 0 when failed, which is ignored. The function should be supported from windows XP and up.
		if prevent:
			ctypes.windll.kernel32.SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
		else:
			ctypes.windll.kernel32.SetThreadExecutionState(ES_CONTINUOUS)

else:
	def preventComputerFromSleeping(prevent):
		#No preventComputerFromSleeping for MacOS and Linux yet.
		pass

class printWindowBasic(wx.Frame):
	"""
	Printing window for USB printing, network printing, and any other type of printer connection we can think off.
	This is only a basic window with minimal information.
	"""
	def __init__(self, parent, printerConnection):
		super(printWindowBasic, self).__init__(parent, -1, style=wx.CLOSE_BOX|wx.CAPTION|wx.SYSTEM_MENU|wx.FRAME_TOOL_WINDOW|wx.FRAME_FLOAT_ON_PARENT, title=_("Printing on %s") % (printerConnection.getName()))
		self._printerConnection = printerConnection
		self._lastUpdateTime = 0

		self.SetSizer(wx.BoxSizer())
		self.panel = wx.Panel(self)
		self.GetSizer().Add(self.panel, 1, flag=wx.EXPAND)
		self.sizer = wx.GridBagSizer(4, 5)
		self.panel.SetSizer(self.sizer)

		self.powerWarningText = wx.StaticText(parent=self.panel,
			id=-1,
			label=_("Your computer is maybe running on battery power.\nConnect your computer to AC power or your print might not finish."),
			style=wx.ALIGN_CENTER)
		self.powerWarningText.SetForegroundColour((169, 68, 66))

		self.statsText = wx.StaticText(self.panel, -1, '\n\n\n')

		self.printButton = wx.Button(self.panel, -1, _("Print"))
		self.pauseButton = wx.Button(self.panel, -1, _("Pause"))
		self.cancelButton = wx.Button(self.panel, -1, _("Cancel print"))
		self.errorLogButton = wx.Button(self.panel, -1, _("Log"))
		self.progress = wx.Gauge(self.panel, -1, range=1000)

		self.sizer.Add(self.powerWarningText, pos=(0, 0), span=(1, 4), flag=wx.EXPAND|wx.BOTTOM, border=5)
		self.sizer.Add(self.statsText, pos=(1, 0), span=(1, 4), flag=wx.LEFT, border=5)
		self.sizer.Add(self.printButton, pos=(2, 0))
		self.sizer.Add(self.pauseButton, pos=(2, 1))
		self.sizer.Add(self.cancelButton, pos=(2, 2))
		self.sizer.Add(self.errorLogButton, pos=(2, 3))

		progress_sizer = wx.BoxSizer()
		progress_sizer.Add(self.progress, flag=wx.EXPAND, border=5)
		self.sizer.Add(progress_sizer, pos=(3, 0))

		self.Bind(wx.EVT_CLOSE, self.OnClose)
		self.printButton.Bind(wx.EVT_BUTTON, self.OnPrint)
		self.pauseButton.Bind(wx.EVT_BUTTON, self.OnPause)
		self.cancelButton.Bind(wx.EVT_BUTTON, self.OnCancel)
		self.errorLogButton.Bind(wx.EVT_BUTTON, self.OnErrorLog)

		self.Layout()
		self.Fit()
		self.Centre()

		self._updateButtonStates()

		self._printerConnection.addCallback(self._doPrinterConnectionUpdate)

		if self._printerConnection.hasActiveConnection() and not self._printerConnection.isActiveConnectionOpen():
			self._printerConnection.openActiveConnection()
		preventComputerFromSleeping(True)

	def OnClose(self, e):
		if self._printerConnection.hasActiveConnection():
			if self._printerConnection.isPrinting():
				pass #TODO: Give warning that the close will kill the print.
			self._printerConnection.closeActiveConnection()
		self._printerConnection.removeCallback(self._doPrinterConnectionUpdate)
		#TODO: When multiple printer windows are open, closing one will enable sleeping again.
		preventComputerFromSleeping(False)
		self.Destroy()

	def OnPrint(self, e):
		self._printerConnection.startPrint()

	def OnCancel(self, e):
		self._printerConnection.cancelPrint()

	def OnPause(self, e):
		if not self._printerConnection.isPaused():
			self.pauseButton.SetLabel(_("Pause"))
		else:
			self.pauseButton.SetLabel(_("Resume"))
		self._printerConnection.pause(not self._printerConnection.isPaused())

	def OnErrorLog(self, e):
		LogWindow(self._printerConnection.getErrorLog())

	def _doPrinterConnectionUpdate(self, connection, extraInfo = None):
		wx.CallAfter(self.__doPrinterConnectionUpdate, connection, extraInfo)
		#temp = [connection.getTemperature(0)]
		#self.temperatureGraph.addPoint(temp, [0], connection.getBedTemperature(), 0)

	def __doPrinterConnectionUpdate(self, connection, extraInfo):
		t = time.time()
		if self._lastUpdateTime + 0.5 > t and extraInfo is None:
			return
		self._lastUpdateTime = t

		if extraInfo is not None:
			self._printerConnection.log.append('< %s\n' % (extraInfo))

		self._updateButtonStates()
		if connection.isPrinting():
			self.progress.SetValue(connection.getPrintProgress() * 1000)
		else:
			self.progress.SetValue(0)
		info = connection.getStatusString()
		info += '\n'
		if self._printerConnection.getTemperature(0) is not None:
			info += 'Noozle temperature: %d ' % self._printerConnection.getTemperature(0)
			info += ('°C').decode('utf-8')
			info += '\n'
		if self._printerConnection.getBedTemperature() > 0:
			info += 'Bed temperature: %d ' % self._printerConnection.getBedTemperature()
			info += ('°C').decode('utf-8')
			info += '\n'
		self.statsText.SetLabel(info)

	def _updateButtonStates(self):
		self.pauseButton.Show(self._printerConnection.hasPause())
		if not self._printerConnection.hasActiveConnection() or self._printerConnection.isActiveConnectionOpen():
			self.printButton.Enable(not self._printerConnection.isPrinting())
			self.pauseButton.Enable(self._printerConnection.isPrinting())
			self.cancelButton.Enable(self._printerConnection.isPrinting())
		else:
			self.printButton.Enable(False)
			self.pauseButton.Enable(False)
			self.cancelButton.Enable(False)
		self.errorLogButton.Show(True)

class TemperatureGraph(wx.Panel):
	def __init__(self, parent):
		super(TemperatureGraph, self).__init__(parent)

		self.Bind(wx.EVT_ERASE_BACKGROUND, self.OnEraseBackground)
		self.Bind(wx.EVT_SIZE, self.OnSize)
		self.Bind(wx.EVT_PAINT, self.OnDraw)

		self._lastDraw = time.time() - 1.0
		self._points = []
		self._backBuffer = None
		self.addPoint([0]*16, [0]*16, 0, 0)

	def OnEraseBackground(self, e):
		pass

	def OnSize(self, e):
		if self._backBuffer is None or self.GetSize() != self._backBuffer.GetSize():
			self._backBuffer = wx.EmptyBitmap(*self.GetSizeTuple())
			self.UpdateDrawing(True)

	def OnDraw(self, e):
		dc = wx.BufferedPaintDC(self, self._backBuffer)

	def UpdateDrawing(self, force=False):
		now = time.time()
		if (not force and now - self._lastDraw < 1.0) or self._backBuffer is None:
			return
		self._lastDraw = now
		dc = wx.MemoryDC()
		dc.SelectObject(self._backBuffer)
		dc.Clear()
		dc.SetFont(wx.SystemSettings.GetFont(wx.SYS_SYSTEM_FONT))
		w, h = self.GetSizeTuple()
		bgLinePen = wx.Pen('#A0A0A0')
		tempPen = wx.Pen('#FF4040')
		tempSPPen = wx.Pen('#FFA0A0')
		tempPenBG = wx.Pen('#FFD0D0')
		bedTempPen = wx.Pen('#4040FF')
		bedTempSPPen = wx.Pen('#A0A0FF')
		bedTempPenBG = wx.Pen('#D0D0FF')

		#Draw the background up to the current temperatures.
		x0 = 0
		t0 = []
		bt0 = 0
		tSP0 = 0
		btSP0 = 0
		for temp, tempSP, bedTemp, bedTempSP, t in self._points:
			x1 = int(w - (now - t))
			for x in xrange(x0, x1 + 1):
				for n in xrange(0, min(len(t0), len(temp))):
					t = float(x - x0) / float(x1 - x0 + 1) * (temp[n] - t0[n]) + t0[n]
					dc.SetPen(tempPenBG)
					dc.DrawLine(x, h, x, h - (t * h / 300))
				bt = float(x - x0) / float(x1 - x0 + 1) * (bedTemp - bt0) + bt0
				dc.SetPen(bedTempPenBG)
				dc.DrawLine(x, h, x, h - (bt * h / 300))
			t0 = temp
			bt0 = bedTemp
			tSP0 = tempSP
			btSP0 = bedTempSP
			x0 = x1 + 1

		#Draw the grid
		for x in xrange(w, 0, -30):
			dc.SetPen(bgLinePen)
			dc.DrawLine(x, 0, x, h)
		tmpNr = 0
		for y in xrange(h - 1, 0, -h * 50 / 300):
			dc.SetPen(bgLinePen)
			dc.DrawLine(0, y, w, y)
			dc.DrawText(str(tmpNr), 0, y - dc.GetFont().GetPixelSize().GetHeight())
			tmpNr += 50
		dc.DrawLine(0, 0, w, 0)
		dc.DrawLine(0, 0, 0, h)

		#Draw the main lines
		x0 = 0
		t0 = []
		bt0 = 0
		tSP0 = []
		btSP0 = 0
		for temp, tempSP, bedTemp, bedTempSP, t in self._points:
			x1 = int(w - (now - t))
			for x in xrange(x0, x1 + 1):
				for n in xrange(0, min(len(t0), len(temp))):
					t = float(x - x0) / float(x1 - x0 + 1) * (temp[n] - t0[n]) + t0[n]
					tSP = float(x - x0) / float(x1 - x0 + 1) * (tempSP[n] - tSP0[n]) + tSP0[n]
					dc.SetPen(tempSPPen)
					dc.DrawPoint(x, h - (tSP * h / 300))
					dc.SetPen(tempPen)
					dc.DrawPoint(x, h - (t * h / 300))
				bt = float(x - x0) / float(x1 - x0 + 1) * (bedTemp - bt0) + bt0
				btSP = float(x - x0) / float(x1 - x0 + 1) * (bedTempSP - btSP0) + btSP0
				dc.SetPen(bedTempSPPen)
				dc.DrawPoint(x, h - (btSP * h / 300))
				dc.SetPen(bedTempPen)
				dc.DrawPoint(x, h - (bt * h / 300))
			t0 = temp
			bt0 = bedTemp
			tSP0 = tempSP
			btSP0 = bedTempSP
			x0 = x1 + 1

		del dc
		self.Refresh(eraseBackground=False)
		self.Update()

		if len(self._points) > 0 and (time.time() - self._points[0][4]) > w + 20:
			self._points.pop(0)

	def addPoint(self, temp, tempSP, bedTemp, bedTempSP):
		if len(self._points) > 0 and time.time() - self._points[-1][4] < 0.5:
			return
		for n in xrange(0, len(temp)):
			if temp[n] is None:
				temp[n] = 0
		for n in xrange(0, len(tempSP)):
			if tempSP[n] is None:
				tempSP[n] = 0
		if bedTemp is None:
			bedTemp = 0
		if bedTempSP is None:
			bedTempSP = 0
		self._points.append((temp[:], tempSP[:], bedTemp, bedTempSP, time.time()))
		wx.CallAfter(self.UpdateDrawing)


class LogWindow(wx.Frame):
	def __init__(self, logText):
		super(LogWindow, self).__init__(None, title=_("Log"))
		self.textBox = wx.TextCtrl(self, -1, logText, style=wx.TE_MULTILINE | wx.TE_DONTWRAP | wx.TE_READONLY)
		self.SetSize((500, 400))
		self.Show(True)
